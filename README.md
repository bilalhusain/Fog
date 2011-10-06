Poor man's private npm repo
---

Files stored locally in tarballs folder. Repository database created on the fly by scanning this folder. The repository information is maintained in-memory all the time.

Usage:
    npm --registry http://localhost:3003/registry publish
    npm --registry http://localhost:3003/registry install module_name

**TODO**

* no authentication

