# domains/

`./new-domain` puts each new domain's folder here. Everything in this folder except this file is git-ignored, on purpose: a real domain's zone ID and records must never be committed to a public repo.

To keep your domains under version control, put them in **your own private repo** and make the folders there with `./new-domain --dir <that repo> --module-source <the module's GitHub address> ...`. See the top of `new-domain` for an example.
