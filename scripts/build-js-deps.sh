#!/bin/bash
set -euo pipefail

# Build all JS dependencies from npm using esbuild.
# Each library is bundled as a self-contained IIFE that sets window.* globals.
# Output goes to Shared/Resources/.
#
# Usage: ./scripts/build-js-deps.sh
#
# To update versions, edit the npm install line below.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/Shared/Resources"
WORK_DIR=$(mktemp -d)

echo "Building JS dependencies..."
echo "  Work dir: $WORK_DIR"
echo "  Output:   $OUTPUT_DIR"
echo ""

cd "$WORK_DIR"
npm init -y --silent > /dev/null

# ============================================================
# Pin versions here for reproducible builds
# ============================================================
npm install --silent \
  highlight.js@11.11.1 \
  katex@0.16.21 \
  mermaid@11.6.0 \
  2>&1 | tail -1

# ============================================================
# 1. highlight.js (common languages → window.hljs)
# ============================================================
cat > entry-hljs.js << 'EOF'
import hljs from 'highlight.js/lib/common';
window.hljs = hljs;
EOF

npx esbuild entry-hljs.js \
  --bundle --minify --format=iife \
  --outfile="$OUTPUT_DIR/highlight.min.js" \
  2>&1 | grep -v "^$"

echo "  highlight.js: $(du -h "$OUTPUT_DIR/highlight.min.js" | awk '{print $1}') ($(node -e "
  global.window = {};
  require('$OUTPUT_DIR/highlight.min.js');
  console.log(window.hljs.listLanguages().length + ' languages');
"))"

# ============================================================
# 2. KaTeX (→ window.katex)
# ============================================================
cat > entry-katex.js << 'EOF'
import katex from 'katex';
window.katex = katex;
EOF

npx esbuild entry-katex.js \
  --bundle --minify --format=iife \
  --outfile="$OUTPUT_DIR/katex.min.js" \
  2>&1 | grep -v "^$"

echo "  katex.js:      $(du -h "$OUTPUT_DIR/katex.min.js" | awk '{print $1}')"

# ============================================================
# 3. KaTeX auto-render (→ window.renderMathInElement)
# ============================================================
cat > entry-katex-auto-render.js << 'EOF'
import renderMathInElement from 'katex/contrib/auto-render';
window.renderMathInElement = renderMathInElement;
EOF

npx esbuild entry-katex-auto-render.js \
  --bundle --minify --format=iife \
  --external:katex \
  --outfile="$OUTPUT_DIR/katex-auto-render.min.js" \
  2>&1 | grep -v "^$"

# katex-auto-render references katex as external — need to patch
# Replace the external require with window.katex
sed -i '' 's/require("katex")/window.katex/g' "$OUTPUT_DIR/katex-auto-render.min.js"

echo "  katex-auto-render: $(du -h "$OUTPUT_DIR/katex-auto-render.min.js" | awk '{print $1}')"

# ============================================================
# 4. Mermaid (→ window.mermaid)
# ============================================================
cat > entry-mermaid.js << 'EOF'
import mermaid from 'mermaid';
window.mermaid = mermaid;
EOF

npx esbuild entry-mermaid.js \
  --bundle --minify --format=iife \
  --outfile="$OUTPUT_DIR/mermaid.min.js" \
  2>&1 | grep -v "^$"

echo "  mermaid.js:    $(du -h "$OUTPUT_DIR/mermaid.min.js" | awk '{print $1}')"

# ============================================================
# 5. KaTeX CSS (copy from npm)
# ============================================================
KATEX_CSS="node_modules/katex/dist/katex.min.css"
cp "$KATEX_CSS" "$OUTPUT_DIR/katex.min.css"

# Copy KaTeX fonts
rm -rf "$OUTPUT_DIR/katex-fonts"
mkdir -p "$OUTPUT_DIR/katex-fonts"
cp node_modules/katex/dist/fonts/*.woff2 "$OUTPUT_DIR/katex-fonts/"

# Patch CSS to reference local font path
sed -i '' 's|fonts/|katex-fonts/|g' "$OUTPUT_DIR/katex.min.css"

echo "  katex.css:     $(du -h "$OUTPUT_DIR/katex.min.css" | awk '{print $1}') + $(ls "$OUTPUT_DIR/katex-fonts/" | wc -l | tr -d ' ') font files"

# ============================================================
# 6. highlight.js GitHub theme CSS
# ============================================================
HLJS_CSS="node_modules/highlight.js/styles/github.min.css"
if [ -f "$HLJS_CSS" ]; then
  cp "$HLJS_CSS" "$OUTPUT_DIR/github.min.css"
else
  # Fallback: download from CDN
  curl -sL "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.11.1/build/styles/github.min.css" \
    -o "$OUTPUT_DIR/github.min.css"
fi
echo "  github.css:    $(du -h "$OUTPUT_DIR/github.min.css" | awk '{print $1}')"

# ============================================================
# Verify all outputs
# ============================================================
echo ""
echo "Verifying..."
FAIL=0
for f in highlight.min.js katex.min.js katex-auto-render.min.js mermaid.min.js katex.min.css github.min.css; do
  if python3 -c "open('$OUTPUT_DIR/$f','rb').read().decode('utf-8')" 2>/dev/null; then
    echo "  ✓ $f (valid UTF-8)"
  else
    echo "  ✗ $f (INVALID UTF-8!)"
    FAIL=1
  fi
done

# Cleanup
rm -rf "$WORK_DIR"

echo ""
if [ $FAIL -eq 0 ]; then
  echo "Done! All JS/CSS dependencies built successfully."
else
  echo "WARNING: Some files have encoding issues."
  exit 1
fi
