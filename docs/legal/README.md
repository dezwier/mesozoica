# Legal documents

Canonical Markdown for public store URLs lives in [`../../backend/app/legal/documents/`](../../backend/app/legal/documents/). Flutter ships identical copies under [`../../flutter/assets/policies/`](../../flutter/assets/policies/). A backend test fails if those two folders drift.

Public HTML is served from the Learn from Data studio site. The API still exposes the old paths and **301s** to these URLs.

| Document | Canonical URL | API redirect |
| --- | --- | --- |
| Privacy policy | https://learnfromdata.ai/mesozoica/privacy | `/privacy` |
| Terms | https://learnfromdata.ai/mesozoica/terms | `/terms` |
| Delete account | https://learnfromdata.ai/mesozoica/delete-account | `/delete-account` |
| Delete data | https://learnfromdata.ai/mesozoica/delete-data | `/delete-data` |

Store submission steps are in [`../store-launch.md`](../store-launch.md). Listing copy is in [`../store_listing.md`](../store_listing.md).
