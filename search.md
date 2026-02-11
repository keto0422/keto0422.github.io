---
layout: page
title: "Search"
permalink: /search/
---

<div id="search-container">
  <input type="text" id="search-input" placeholder="Type a keyword..." class="search-input" />
  <div id="results-container"></div>
</div>

<style>
  .search-input {
    padding: 8px;
    width: 100%;
    max-width: 400px;
    margin-bottom: 10px;
    font-size: 16px;
    border: 1px solid #ddd;
    border-radius: 4px;
  }

  #results-container {
    margin-top: 20px;
  }

  .result-item {
    margin-bottom: 20px;
    padding-bottom: 15px;
    border-bottom: 1px solid #eee;
  }

  .result-title {
    font-size: 18px;
    font-weight: bold;
    margin-bottom: 5px;
  }

  .result-date {
    color: #777;
    font-size: 14px;
    margin-bottom: 8px;
  }

  .result-snippet {
    font-size: 14px;
    color: #333;
  }

  .highlight {
    background-color: yellow;
    font-weight: bold;
  }
</style>

<script src="https://cdnjs.cloudflare.com/ajax/libs/lunr.js/2.3.9/lunr.min.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function() {
  let idx;
  let documents = {};

  const searchInput = document.getElementById('search-input');
  const resultsContainer = document.getElementById('results-container');

  fetch('{{ site.baseurl }}/search.json')
    .then(response => response.json())
    .then(data => {
      data.docs.forEach(doc => {
        documents[doc.url] = doc;
      });

      idx = lunr(function() {
        this.ref('url');
        this.field('title', { boost: 10 });
        this.field('content');

        this.pipeline.remove(lunr.stemmer);
        this.searchPipeline.remove(lunr.stemmer);
        this.tokenizer.separator = /[\s\-]+/;

        data.docs.forEach(doc => {
          this.add({
            'url': doc.url,
            'title': doc.title,
            'content': doc.content,
            'date': doc.date
          });
        });
      });

      searchInput.disabled = false;
      searchInput.placeholder = "Enter a search term";
    })
    .catch(error => {
      console.error('Failed to load the search index:', error);
      resultsContainer.innerHTML = '<p>Unable to load search data.</p>';
    });

  searchInput.addEventListener('input', function() {
    const query = this.value.trim();

    if (query.length < 1) {
      resultsContainer.innerHTML = '';
      return;
    }

    if (!idx) {
      resultsContainer.innerHTML = '<p>Loading search index...</p>';
      return;
    }

    const wildcardQuery = query.split(' ')
      .map(term => term + '*')
      .join(' ');

    const results = idx.search(wildcardQuery);

    if (results.length < 3 && query.length > 2) {
      const fuzzyQuery = query.split(' ')
        .map(term => term + '~1')
        .join(' ');

      const fuzzyResults = idx.search(fuzzyQuery);
      fuzzyResults.forEach(result => {
        if (!results.some(r => r.ref === result.ref)) {
          results.push(result);
        }
      });
    }

    if (results.length === 0) {
      const matchedDocs = Object.values(documents).filter(doc => {
        return doc.title.toLowerCase().includes(query.toLowerCase()) ||
               doc.content.toLowerCase().includes(query.toLowerCase());
      });

      if (matchedDocs.length > 0) {
        let resultHtml = '';
        matchedDocs.forEach(doc => {
          let snippet = doc.content.length > 150
            ? doc.content.substring(0, 150) + '...'
            : doc.content;

          const titleHighlighted = highlightText(doc.title, query);
          const snippetHighlighted = highlightText(snippet, query);

          resultHtml += `
            <div class="result-item">
              <div class="result-title">
                <a href="${doc.url}">${titleHighlighted}</a>
              </div>
              <div class="result-date">${doc.date}</div>
              <div class="result-snippet">${snippetHighlighted}</div>
            </div>
          `;
        });
        resultsContainer.innerHTML = resultHtml;
      } else {
        resultsContainer.innerHTML = '<p>No results found.</p>';
      }
      return;
    }

    let resultHtml = '';
    results.forEach(result => {
      const doc = documents[result.ref];
      let snippet = '';

      const lowerContent = doc.content.toLowerCase();
      const lowerQuery = query.toLowerCase();
      const index = lowerContent.indexOf(lowerQuery);

      if (index !== -1) {
        const start = Math.max(0, index - 60);
        const end = Math.min(doc.content.length, index + query.length + 60);
        snippet = doc.content.substring(start, end);

        if (start > 0) snippet = '...' + snippet;
        if (end < doc.content.length) snippet += '...';
      } else {
        snippet = doc.content.length > 150
          ? doc.content.substring(0, 150) + '...'
          : doc.content;
      }

      const titleHighlighted = highlightText(doc.title, query);
      const snippetHighlighted = highlightText(snippet, query);

      resultHtml += `
        <div class="result-item">
          <div class="result-title">
            <a href="${doc.url}">${titleHighlighted}</a>
          </div>
          <div class="result-date">${doc.date}</div>
          <div class="result-snippet">${snippetHighlighted}</div>
        </div>
      `;
    });

    resultsContainer.innerHTML = resultHtml;
  });

  function highlightText(text, query) {
    if (!query || query.trim() === '') return text;

    const words = query.trim().toLowerCase().split(/\s+/);
    let result = text;

    words.forEach(word => {
      if (word.length < 2) return;
      const regex = new RegExp('(' + word + ')', 'gi');
      result = result.replace(regex, '<span class="highlight">$1</span>');
    });

    return result;
  }

  searchInput.disabled = true;
  searchInput.placeholder = "Loading search index...";
});
</script>
