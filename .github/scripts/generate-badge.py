# Generate coverage badge artifacts from coverage.json
# Usage: python3 .github/scripts/generate-badge.py < coverage.json
import json, sys

data = json.load(sys.stdin)
cov = data.get("coverage", 0)
gen = data.get("generated_at", "")

color = "red"
if cov >= 80: color = "brightgreen"
elif cov >= 60: color = "yellowgreen"
elif cov >= 40: color = "yellow"
elif cov >= 20: color = "orange"

badge_json = {
    "schemaVersion": 1,
    "label": "coverage",
    "message": f"{cov}%",
    "color": color,
    "generated_at": gen
}

with open("badge.json", "w") as f:
    json.dump(badge_json, f, indent=2)

# Generate lightweight inline SVG badge
pct = f"{cov:.1f}%"
label_w = 62
val_w = max(len(pct) * 8 + 10, 40)
total_w = label_w + val_w

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" height="20" role="img" aria-label="coverage: {pct}">
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="r">
    <rect width="{total_w}" height="20" rx="3" fill="#fff"/>
  </clipPath>
  <g clip-path="url(#r)">
    <rect width="{label_w}" height="20" fill="#555"/>
    <rect x="{label_w}" width="{val_w}" height="20" fill="#{"4c1" if cov >= 80 else "a3a"}"/>
    <rect width="{total_w}" height="20" fill="url(#s)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11">
    <text x="{label_w // 2}" y="15" fill="#010101" fill-opacity=".3">coverage</text>
    <text x="{label_w // 2}" y="14">coverage</text>
    <text x="{label_w + val_w // 2}" y="15" fill="#010101" fill-opacity=".3">{pct}</text>
    <text x="{label_w + val_w // 2}" y="14">{pct}</text>
  </g>
</svg>'''

with open("badge.svg", "w") as f:
    f.write(svg)

new_data = {
    "schemaVersion": 1,
    "label": "coverage",
    "message": f"{cov}%",
    "color": color,
    "generated_at": gen,
    "coverage": cov
}
with open("coverage.json", "w") as f:
    json.dump(new_data, f, indent=2)
