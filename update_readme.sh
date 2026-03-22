#!/usr/bin/env bash
set -euo pipefail

GITHUB_USER="Cygra"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="$SCRIPT_DIR/README.md"

# macOS/Linux compatible: 6 months ago
if [[ "$OSTYPE" == "darwin"* ]]; then
  SINCE_6M=$(date -u -v-6m +%Y-%m-%dT%H:%M:%SZ)
else
  SINCE_6M=$(date -u -d '6 months ago' +%Y-%m-%dT%H:%M:%SZ)
fi
SINCE_2024="2024-01-01T00:00:00Z"

cd "$SCRIPT_DIR"

echo "📦 Pulling latest changes..."
git pull origin main

QUERY='query($login: String!, $since2024: GitTimestamp!, $since6m: GitTimestamp!) {
  user(login: $login) {
    repositories(first: 100, ownerAffiliations: OWNER, privacy: PUBLIC, isFork: false, isArchived: false) {
      nodes {
        name
        url
        description
        repositoryTopics(first: 8) {
          nodes { topic { name } }
        }
        defaultBranchRef {
          target {
            ... on Commit {
              c2024: history(since: $since2024) { totalCount }
              c6m:   history(since: $since6m)   { totalCount }
            }
          }
        }
      }
    }
  }
}'

echo "🔍 Fetching repository data from GitHub..."
RESULT=$(gh api graphql \
  -f query="$QUERY" \
  -f login="$GITHUB_USER" \
  -f since2024="$SINCE_2024" \
  -f since6m="$SINCE_6M")

# Top 10 repos by commit count since 2024-01-01
TOP10_ROWS=$(printf '%s' "$RESULT" | jq -r '
  .data.user.repositories.nodes
  | map({
      name: .name,
      url:  .url,
      desc: ((.description // "") | gsub("\\|"; "\\\\|") | if . == "" then "—" else . end),
      tags: (.repositoryTopics.nodes | map("<kbd>\(.topic.name)</kbd>") | join(" ")),
      n:    (.defaultBranchRef.target.c2024.totalCount // 0)
    })
  | map(select(.n > 0))
  | sort_by(-.n)
  | .[0:10]
  | map("| [\(.name)](\(.url)) | \(.desc) | \(.tags) | **\(.n)** |")
  | .[]
')

# All repos with commits in the last 6 months, sorted by activity
RECENT_ROWS=$(printf '%s' "$RESULT" | jq -r '
  .data.user.repositories.nodes
  | map({
      name: .name,
      url:  .url,
      desc: ((.description // "") | gsub("\\|"; "\\\\|") | if . == "" then "—" else . end),
      tags: (.repositoryTopics.nodes | map("<kbd>\(.topic.name)</kbd>") | join(" ")),
      n:    (.defaultBranchRef.target.c6m.totalCount // 0)
    })
  | map(select(.n > 0))
  | sort_by(-.n)
  | map("| [\(.name)](\(.url)) | \(.desc) | \(.tags) |")
  | .[]
')

echo "✏️  Rebuilding README.md..."

TMP="$(mktemp)"

# Keep everything up to and including the first `---`
awk '/^---$/ { print; exit } { print }' "$README" > "$TMP"

# Append the dynamic sections
{
  printf '\n'
  printf '## 🌱 Recently Active (Last 6 Months)\n'
  printf '\n'
  printf '| Repository | Description | Topics |\n'
  printf '|:-----------|:------------|:-------|\n'
  printf '%s\n' "$RECENT_ROWS"
  printf '\n'
  printf '## 🔥 Most Active Repositories (Since 2024)\n'
  printf '\n'
  printf '| Repository | Description | Topics | Commits |\n'
  printf '|:-----------|:------------|:-------|--------:|\n'
  printf '%s\n' "$TOP10_ROWS"
  printf '\n'
  printf '%s\n' '---'
  printf '\n'
  printf '![](https://raw.githubusercontent.com/Cygra/github-stats/master/generated/overview.svg#gh-dark-mode-only)\n'
  printf '![](https://raw.githubusercontent.com/Cygra/github-stats/master/generated/overview.svg#gh-light-mode-only)\n'
  printf '![](https://raw.githubusercontent.com/Cygra/github-stats/master/generated/languages.svg#gh-dark-mode-only)\n'
  printf '![](https://raw.githubusercontent.com/Cygra/github-stats/master/generated/languages.svg#gh-light-mode-only)\n'
} >> "$TMP"

mv "$TMP" "$README"
echo "✅ README.md updated."

# Commit and push
git add README.md
git commit -m "chore: update activity sections [$(date +%Y-%m-%d)]"
git push origin main
echo "🚀 Pushed to GitHub."
