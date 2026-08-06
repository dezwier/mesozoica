"""Business-feature packages.

Cross-feature callers must import a feature's ``public`` module.  Legacy
modules remain behind those facades while the feature-first migration is in
progress, keeping HTTP and persistence contracts stable.
"""

