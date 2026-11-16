# The bundled "terraform" ruleset checks general Terraform hygiene (unused
# variables, missing version pins, deprecated syntax). There is no tflint
# ruleset for Cloudflare, so this is the one that applies to this project.
# "recommended" is the sensible default; "all" adds stricter style rules that
# would mostly be noise here.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
