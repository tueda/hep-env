#!/usr/bin/env python3
"""Validate the tag ref exposed by pre-commit during a push."""

import datetime
import os
import re
import subprocess
from collections.abc import Iterable

RELEASE_TAG_RE = re.compile(r"v[0-9]{4,}\.(?:0[1-9]|1[0-2])\.(?:0|[1-9][0-9]*)")


def validate(tag: str, today: datetime.date, existing_tags: Iterable[str]) -> None:
    """Validate a release tag."""
    prefix = f"v{today:%Y.%m}."
    release_numbers = [
        int(existing_tag.removeprefix(prefix))
        for existing_tag in existing_tags
        if existing_tag.startswith(prefix) and RELEASE_TAG_RE.fullmatch(existing_tag)
    ]
    expected = f"{prefix}{max(release_numbers, default=-1) + 1}"

    if tag != expected:
        msg = f"Invalid release tag: {tag}; expected: {expected}"
        raise ValueError(msg)


def main() -> None:
    """Validate the destination ref provided by pre-commit."""
    ref = os.environ.get("PRE_COMMIT_REMOTE_BRANCH")
    remote = os.environ.get("PRE_COMMIT_REMOTE_NAME")

    if not ref or not remote:
        msg = "Release tag check requires pre-commit's pre-push context."
        raise RuntimeError(msg)

    if not ref.startswith("refs/tags/"):
        return

    tag = ref.removeprefix("refs/tags/")

    today = datetime.datetime.now().astimezone().date()
    prefix = f"v{today:%Y.%m}."

    result = subprocess.run(  # noqa: S603
        [  # noqa: S607
            "git",
            "ls-remote",
            "--tags",
            "--refs",
            remote,
            f"refs/tags/{prefix}*",
        ],
        capture_output=True,
        check=True,
        text=True,
    )

    existing_tags = [
        line.split()[1].removeprefix("refs/tags/")
        for line in result.stdout.splitlines()
    ]

    validate(tag, today, existing_tags)


if __name__ == "__main__":
    main()
