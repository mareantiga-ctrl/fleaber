"""Entry point Fleaber PS Reader."""

from fleaber_ps.app.main_window import run_app
from fleaber_ps.diagnostic.logging_setup import setup_logging


def main() -> None:
    setup_logging()
    run_app()


if __name__ == "__main__":
    main()
