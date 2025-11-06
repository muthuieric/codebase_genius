
__version__ = "2.5.3"
version_info = tuple(
    int(v) if v.isdigit() else v
    for v in __version__.split(".")
)


__all__ = (
    "version_info",
    "__version__",
)
