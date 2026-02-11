source "https://rubygems.org"

# Jekyll version
gem "jekyll", "~> 4.4.1"

# Default theme
gem "minima", "~> 2.5"

# Jekyll plugins
group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.12"
  gem "jekyll-paginate"
  gem "jekyll-seo-tag"
  gem "jekyll-sitemap"
  gem "jekyll-compose"
  # Lunr.js search is implemented manually, no extra plugin needed
end

# Gems for Windows/JRuby compatibility
platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem "tzinfo", ">= 1", "< 3"
  gem "tzinfo-data"
end

# Windows performance improvement
gem "wdm", "~> 0.1", :platforms => [:mingw, :x64_mingw, :mswin]

# JRuby compatibility
gem "http_parser.rb", "~> 0.6.0", :platforms => [:jruby]

# Web server for Jekyll 4.3.0+
gem "webrick", "~> 1.8"
