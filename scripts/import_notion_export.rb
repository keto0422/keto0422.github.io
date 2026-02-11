#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "open3"
require "optparse"
require "pathname"
require "set"
require "time"
require "tmpdir"
require "yaml"

OPTIONS = {
  date: nil,
  timezone: "+0900",
  author: "Keto",
  dry_run: false
}.freeze

MARKDOWN_LINK = /(!?\[[^\]]*\]\()([^)]+)(\))/m.freeze
HTML_LINK = /(\b(?:src|href)=["'])([^"']+)(["'])/i.freeze

def run!(*cmd)
  _out, err, status = Open3.capture3(*cmd)
  return if status.success?

  abort "[ERROR] Command failed: #{cmd.join(' ')}\n#{err}"
end

def parse_args
  options = OPTIONS.dup

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: bin/import-notion-export <zip-path> [options]"
    opts.on("--date DATE", "Forced post date (YYYY-MM-DD)") { |v| options[:date] = v }
    opts.on("--timezone TZ", "Timezone (default: +0900)") { |v| options[:timezone] = v }
    opts.on("--author NAME", "Post author (default: Keto)") { |v| options[:author] = v }
    opts.on("--dry-run", "Preview only, do not write files") { options[:dry_run] = true }
    opts.on("-h", "--help", "Show help") do
      puts opts
      exit 0
    end
  end

  parser.parse!
  zip_path = ARGV.shift
  abort parser.banner unless zip_path

  [zip_path, options]
end

def unzip_recursively(zip_path, extract_root)
  run!("unzip", "-o", "-q", zip_path, "-d", extract_root)

  loop do
    nested = Dir.glob(File.join(extract_root, "**", "*.zip"))
    break if nested.empty?

    nested.each do |child_zip|
      run!("unzip", "-o", "-q", child_zip, "-d", File.dirname(child_zip))
      File.delete(child_zip) if File.file?(child_zip)
    end
  end
end

def strip_notion_suffix(filename)
  name = filename.dup
  name.sub!(/\s+[0-9a-f]{32}\z/i, "")
  name.sub!(/\s+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i, "")
  name.strip
end

def extract_notion_id(filename)
  match = filename.match(/([0-9a-f]{32})\z/i)
  return match[1] if match

  uuid = filename.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z/i)
  return uuid[1].delete("-") if uuid

  nil
end

def slugify(value, fallback)
  ascii = value
          .encode("ASCII", invalid: :replace, undef: :replace, replace: "")
          .downcase
          .gsub(/[^a-z0-9\s-]/, " ")
          .strip
          .gsub(/\s+/, "-")
          .gsub(/-+/, "-")
  ascii.empty? ? fallback : ascii
end

def split_url_and_suffix(raw_url)
  match = raw_url.match(/\A([^?#]+)(.*)\z/)
  return [raw_url, ""] unless match

  [match[1], match[2]]
end

def absolute_url?(url)
  url.start_with?("/", "#") || url.match?(/\A[a-z][a-z0-9+\-.]*:/i)
end

def encode_url_path(path)
  path.split("/").map { |segment| CGI.escape(segment).tr("+", "%20") }.join("/")
end

def normalize_title(raw)
  stripped = strip_notion_suffix(raw)
  stripped.empty? ? raw : stripped
end

def infer_categories(title, body)
  text = "#{title}\n#{body}".downcase
  categories = []
  categories << "1-day" if text.match?(/cve-\d{4}-\d+/i) || text.include?("1-day") || text.include?("exploit")
  categories << "ctf" if text.include?("ctf")
  categories << "writeup" if categories.empty?
  categories.uniq
end

def infer_tags(title, body)
  text = "#{title}\n#{body}".downcase
  tags = ["notion-import"]
  tags << "exploit" if text.include?("exploit")
  tags << "cve" if text.match?(/cve-\d{4}-\d+/i)
  tags << "ctf" if text.include?("ctf")
  tags.uniq
end

def pick_date(content, source_path, forced_date, timezone)
  return Time.parse("#{forced_date} 09:00:00 #{timezone}") if forced_date

  content.each_line.take(30).each do |line|
    next unless line.match?(/^(date|created(?: time)?|published(?: time)?)\s*:/i)

    _, value = line.split(":", 2)
    begin
      return Time.parse(value.strip)
    rescue StandardError
      next
    end
  end

  File.mtime(source_path)
end

def unique_slug(base_slug, used)
  slug = base_slug
  index = 2
  while used.include?(slug)
    slug = "#{base_slug}-#{index}"
    index += 1
  end
  used << slug
  slug
end

def local_path_from_url(raw_url)
  trimmed = raw_url.strip
  if trimmed.start_with?("<") && trimmed.include?(">")
    target = trimmed[/\A<([^>]+)>/, 1]
    suffix = trimmed.sub(/\A<[^>]+>/, "")
    return [target, suffix]
  end

  match = trimmed.match(/\A(\S+)(\s+.*)?\z/m)
  return [trimmed, ""] unless match

  [match[1], match[2].to_s]
end

def rewrite_local_url(raw_url, source_dir:, export_root:, asset_base:, copied_assets:, dry_run:)
  url_part, tail = local_path_from_url(raw_url)
  return raw_url if absolute_url?(url_part)

  path_part, suffix = split_url_and_suffix(url_part)
  decoded = CGI.unescape(path_part)
  source_path = File.expand_path(decoded, source_dir)
  return raw_url unless source_path.start_with?(export_root)
  return raw_url unless File.file?(source_path)

  rel = Pathname.new(source_path).relative_path_from(Pathname.new(source_dir)).to_s
  safe_rel = rel.split("/").reject { |segment| segment.empty? || segment == "." || segment == ".." }.join("/")
  target_rel = File.join(asset_base, safe_rel)
  target_path = File.join("assets", "notion", target_rel)

  unless copied_assets.include?(source_path)
    FileUtils.mkdir_p(File.dirname(target_path)) unless dry_run
    FileUtils.cp(source_path, target_path) unless dry_run
    copied_assets << source_path
  end

  encoded = encode_url_path(target_rel)
  "/assets/notion/#{encoded}#{suffix}#{tail}"
end

def rewrite_body_links(body, source_dir:, export_root:, asset_base:, copied_assets:, dry_run:)
  rewritten = body.gsub(MARKDOWN_LINK) do
    prefix = Regexp.last_match(1)
    raw_url = Regexp.last_match(2)
    suffix = Regexp.last_match(3)
    updated = rewrite_local_url(raw_url, source_dir: source_dir, export_root: export_root, asset_base: asset_base,
                                         copied_assets: copied_assets, dry_run: dry_run)
    "#{prefix}#{updated}#{suffix}"
  end

  rewritten.gsub(HTML_LINK) do
    prefix = Regexp.last_match(1)
    raw_url = Regexp.last_match(2)
    suffix = Regexp.last_match(3)
    updated = rewrite_local_url(raw_url, source_dir: source_dir, export_root: export_root, asset_base: asset_base,
                                         copied_assets: copied_assets, dry_run: dry_run)
    "#{prefix}#{updated}#{suffix}"
  end
end

def build_front_matter(title:, time:, timezone:, author:, categories:, tags:)
  post_time = Time.new(time.year, time.month, time.day, time.hour, time.min, time.sec, timezone)
  {
    "layout" => "post",
    "title" => title,
    "date" => post_time.strftime("%Y-%m-%d %H:%M:%S %z"),
    "author" => author,
    "categories" => categories,
    "tags" => tags
  }
end

def write_post(post_path, front_matter, body, dry_run)
  yaml = front_matter.to_yaml.sub(/\A---\s*\n/, "")
  content = +"---\n#{yaml}---\n\n#{body.rstrip}\n"
  return if dry_run

  File.write(post_path, content)
end

def copy_csv_files(export_root, import_token, dry_run)
  csv_files = Dir.glob(File.join(export_root, "**", "*.csv"))
  copied = []
  csv_files.each do |csv_file|
    rel = Pathname.new(csv_file).relative_path_from(Pathname.new(export_root)).to_s
    target = File.join("assets", "notion", import_token, "tables", rel)
    FileUtils.mkdir_p(File.dirname(target)) unless dry_run
    FileUtils.cp(csv_file, target) unless dry_run
    copied << target
  end
  copied
end

zip_path, options = parse_args
zip_abs = File.expand_path(zip_path)
abort "[ERROR] Zip file not found: #{zip_path}" unless File.file?(zip_abs)

used_slugs = Set.new
copied_assets = Set.new
import_token = Time.now.strftime("%Y%m%d-%H%M%S")
created_posts = []

Dir.mktmpdir("notion-import-") do |tmp|
  extract_root = File.join(tmp, "extract")
  FileUtils.mkdir_p(extract_root)
  unzip_recursively(zip_abs, extract_root)

  markdown_files = Dir.glob(File.join(extract_root, "**", "*.md")).sort
  abort "[ERROR] No markdown files found in export." if markdown_files.empty?

  FileUtils.mkdir_p("_posts") unless options[:dry_run]
  FileUtils.mkdir_p(File.join("assets", "notion")) unless options[:dry_run]

  markdown_files.each do |md_path|
    source_dir = File.dirname(md_path)
    raw_name = File.basename(md_path, ".md")
    notion_id = extract_notion_id(raw_name)
    title = normalize_title(raw_name)

    id_fallback = notion_id ? notion_id[0, 8] : "post"
    base_slug = slugify(title, id_fallback)
    slug = unique_slug(base_slug, used_slugs)

    body = File.read(md_path)
    rewritten_body = rewrite_body_links(
      body,
      source_dir: source_dir,
      export_root: extract_root,
      asset_base: File.join(import_token, slug),
      copied_assets: copied_assets,
      dry_run: options[:dry_run]
    )

    post_time = pick_date(rewritten_body, md_path, options[:date], options[:timezone])
    front_matter = build_front_matter(
      title: title,
      time: post_time,
      timezone: options[:timezone],
      author: options[:author],
      categories: infer_categories(title, rewritten_body),
      tags: infer_tags(title, rewritten_body)
    )

    date_prefix = post_time.strftime("%Y-%m-%d")
    post_filename = "#{date_prefix}-#{slug}.md"
    post_path = File.join("_posts", post_filename)
    index = 2
    while File.exist?(post_path)
      post_filename = "#{date_prefix}-#{slug}-#{index}.md"
      post_path = File.join("_posts", post_filename)
      index += 1
    end

    write_post(post_path, front_matter, rewritten_body, options[:dry_run])
    created_posts << post_path
  end

  copied_csv = copy_csv_files(extract_root, import_token, options[:dry_run])

  puts "[OK] Imported #{created_posts.size} markdown file(s)."
  created_posts.each { |path| puts " - #{path}" }
  puts "[OK] Copied #{copied_assets.size} attachment file(s) to assets/notion/#{import_token}/"
  puts "[OK] Copied #{copied_csv.size} csv file(s)." unless copied_csv.empty?
  puts "[DRY-RUN] No files were written." if options[:dry_run]
end
