# Keto's Blog

이 저장소는 [Jekyll](https://jekyllrb.com/)을 사용한 블로그입니다.

## 개발 환경 설정

```bash
bundle install
```

로컬 서버 실행:

```bash
bundle exec jekyll serve
```

## 새 글 작성하기

[jekyll-compose](https://github.com/jekyll/jekyll-compose) 플러그인을 사용하여 손쉽게 새 글과 초안을 생성할 수 있습니다.

새 글(post) 생성:

```bash
bin/new-post "제목"
```

초안(draft) 생성:

```bash
bin/new-draft "제목"
```

생성된 파일을 수정하여 내용을 작성한 후 커밋하면 됩니다.

