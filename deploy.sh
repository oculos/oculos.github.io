#!/bin/bash
JEKYLL_ENV=production bundle exec jekyll build
git add *
git commit -m "new version of the site"
git push
docker buildx build --platform=linux/amd64 -t ghcr.io/oculos/francisaugusto .
echo $CR_PAT | docker login ghcr.io -u oculos --password-stdin
docker push ghcr.io/oculos/francisaugusto
