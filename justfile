default:
  @just --list

# Run the hugo server for local dev
serve:
  hugo serve -D

# Create a new file for a post
new-post slug:
  touch content/posts/{{slug}}.md

# Create the GitHub Discussion backing a post
create-discussion slug:
  # https://docs.github.com/en/rest/teams/discussions?apiVersion=2022-11-28#list-discussions
  @echo "TODO"
