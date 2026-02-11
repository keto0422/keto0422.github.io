# Keto's Blog

This repository contains a Jekyll-based blog focused on security write-ups.

## Setup

```bash
bundle install
```

Run the local server:

```bash
bundle exec jekyll serve
```

## Create a New Post

This project uses [jekyll-compose](https://github.com/jekyll/jekyll-compose) to create posts and drafts quickly.

Create a post:

```bash
bin/new-post "Post title"
```

Create a draft:

```bash
bin/new-draft "Draft title"
```

## Import Notion Export

You can import a Notion `Markdown & CSV` export zip directly into this blog:

```bash
bin/import-notion-export exported.zip
```

Options:

```bash
bin/import-notion-export exported.zip --date 2026-02-11 --author "Keto"
bin/import-notion-export exported.zip --dry-run
```

What it does:

- Automatically extracts nested zip files (`ExportBlock-...Part-1.zip`)
- Converts `.md` files into `_posts/YYYY-MM-DD-slug.md`
- Copies attachments/images to `assets/notion/<import-token>/...` and rewrites links
- Stores exported `.csv` files in `assets/notion/<import-token>/tables/...`
