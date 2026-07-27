-- NutriEat — retailer search-URL templates (Level 2 shopping links). Additive only.
-- {q} is replaced with the URL-encoded ingredient search term at request time.

alter table retailers add column if not exists search_url_template text;

update retailers set search_url_template = t.tmpl
from (values
  ('tesco',      'https://www.tesco.com/groceries/en-GB/search?query={q}'),
  ('sainsburys', 'https://www.sainsburys.co.uk/gol-ui/SearchResults/{q}'),
  ('asda',       'https://groceries.asda.com/search/{q}'),
  ('morrisons',  'https://groceries.morrisons.com/search?entry={q}'),
  ('iceland',    'https://www.iceland.co.uk/search?q={q}'),
  ('ocado',      'https://www.ocado.com/search?entry={q}'),
  ('waitrose',   'https://www.waitrose.com/ecom/shop/search?searchTerm={q}')
) as t(slug, tmpl)
where retailers.slug = t.slug;
