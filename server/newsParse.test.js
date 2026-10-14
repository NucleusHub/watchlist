import test from 'node:test'
import assert from 'node:assert/strict'
import { parseFeed, plain, merge } from './newsParse.js'

const rss = `<rss><channel><title>Feed</title>
<item><title><![CDATA[Dune &#8217;Part Three&#8217; &amp; more]]></title><link>https://v.com/a</link>
<pubDate>Tue, 14 Oct 2026 10:00:00 +0000</pubDate>
<description><![CDATA[<p>Villeneuve <b>returns</b>.</p><img src="https://v.com/i.jpg">]]></description>
<media:thumbnail url="https://v.com/t.jpg?a=1&amp;b=2"/></item>
<item><title>No link</title></item>
<item><title>Bad scheme</title><link>javascript:alert(1)</link></item>
</channel></rss>`

test('parses RSS items and drops unusable ones', () => {
  const [a, ...rest] = parseFeed(rss, 'Variety')
  assert.equal(rest.length, 0)
  assert.equal(a.title, 'Dune ’Part Three’ & more')
  assert.equal(a.link, 'https://v.com/a')
  assert.equal(a.published, '2026-10-14T10:00:00.000Z')
  assert.equal(a.image, 'https://v.com/t.jpg?a=1&b=2')
  assert.equal(a.summary, 'Villeneuve returns .')
  assert.equal(a.source, 'Variety')
})

test('parses Atom entries and falls back to an inline image', () => {
  const atom = `<feed><entry><title>Hi</title><link href="https://x.com/p"/><updated>2026-01-02T03:04:05Z</updated>
<summary>&lt;img src="https://x.com/i.png"&gt; text</summary></entry></feed>`
  const [a] = parseFeed(atom, 'X')
  assert.equal(a.link, 'https://x.com/p')
  assert.equal(a.published, '2026-01-02T03:04:05.000Z')
  assert.equal(a.summary, 'text')
})

test('plain strips tags and decodes numeric entities', () => {
  assert.equal(plain('<a href="#">A&nbsp;&#x26;&#38; B</a>'), 'A && B')
})

test('merge sorts newest first and dedupes links and headlines', () => {
  const mk = (title, link, published) => ({ title, link, published, source: 's', image: null, summary: '' })
  const out = merge([mk('Old', 'https://a/1', '2026-01-01T00:00:00.000Z'), mk('New!', 'https://a/2', '2026-02-01T00:00:00.000Z'),
    mk('new', 'https://b/2', '2026-02-02T00:00:00.000Z'), mk('Old2', 'https://a/1', '2026-03-01T00:00:00.000Z')])
  assert.deepEqual(out.map((a) => a.link), ['https://a/1', 'https://b/2'])
})

test('caps parsed blocks and stays fast on unclosed tags', () => {
  const many = '<item><title>t</title><link>https://a.com/x</link></item>'.repeat(500)
  assert.equal(parseFeed(many, 'S').length, 200)
  const start = Date.now()
  assert.deepEqual(parseFeed('<item>'.repeat(200000), 'S'), [])
  assert.ok(Date.now() - start < 2000)
})
