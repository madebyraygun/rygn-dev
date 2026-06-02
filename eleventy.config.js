const crypto = require("crypto");
const fs = require("fs");
const series = require("./src/_data/series.json");

module.exports = function(eleventyConfig) {
  eleventyConfig.addPassthroughCopy("src/static");
  eleventyConfig.addPassthroughCopy("src/admin");

  // Cache-bust an asset with a short content hash: /static/style.css?v=<hash>
  eleventyConfig.addFilter("bust", (urlPath) => {
    try {
      const hash = crypto
        .createHash("md5")
        .update(fs.readFileSync(`src${urlPath}`))
        .digest("hex")
        .slice(0, 8);
      return `${urlPath}?v=${hash}`;
    } catch (e) {
      return urlPath;
    }
  });

  eleventyConfig.addFilter("postDate", (value) =>
    new Date(value).toISOString().slice(0, 10)
  );

  eleventyConfig.addCollection("posts", (collectionApi) =>
    [...collectionApi.getFilteredByTag("post")].reverse()
  );

  eleventyConfig.addShortcode("seriesNav", function(seriesKey, currentUrl) {
    const s = series[seriesKey];
    if (!s) return "";
    const items = s.parts.map((part) => {
      const label = `<span class="series-nav__num">${part.label}</span>`;
      if (part.url === currentUrl) {
        return `<li class="series-nav__item is-current" aria-current="true">${label} ${part.title} <span class="series-nav__here">← you are here</span></li>`;
      }
      return `<li class="series-nav__item">${label} <a href="${part.url}">${part.title}</a></li>`;
    }).join("");
    return `<nav class="series-nav" aria-label="Series navigation">` +
      `<p class="series-nav__head"><a href="${s.indexUrl}">${s.title}</a> &middot; the full series</p>` +
      `<ol class="series-nav__list">${items}</ol>` +
      `</nav>`;
  });

  return {
    dir: {
      input: "src",
      output: "_site"
    }
  };
};
