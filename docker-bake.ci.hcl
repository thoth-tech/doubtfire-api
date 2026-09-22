group "default" {
  targets = ["api"]
}

target "api" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "ci"
  tags       = ["doubtfire-api-ci:local"]
  cache-from = ["type=gha,scope=doubtfire-api"]
}

target "api-cache-writer" {
  inherits = ["api"]
  cache-to = ["type=gha,mode=max,scope=doubtfire-api"]
}

target "texlive" {
  context    = "."
  dockerfile = "texlive.Dockerfile"
  tags       = ["doubtfire-texlive-development:local"]
  cache-from = ["type=gha,scope=texlive"]
}

target "texlive-cache-writer" {
  inherits = ["texlive"]
  cache-to = ["type=gha,mode=max,scope=texlive"]
}

target "jplag" {
  context    = "."
  dockerfile = "jplag.Dockerfile"
  tags       = ["doubtfire-jplag-development:local"]
  cache-from = ["type=gha,scope=jplag"]
}

target "jplag-cache-writer" {
  inherits = ["jplag"]
  cache-to = ["type=gha,mode=max,scope=jplag"]
}
