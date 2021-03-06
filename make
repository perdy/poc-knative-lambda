#!/usr/bin/env python3
"""Run script.
"""
import logging
import os
import shlex
import shutil
import subprocess
import sys
from typing import List

logger = logging.getLogger("cli")

IMAGE = f"poc-knative-lambda"
APP_PATH = f"/srv/app"
LOCAL_PATH = os.path.abspath(os.path.dirname(__file__))


def request_install_requirement(package: str):
    response = None
    while response is None:
        response = input(f"Package {package} is not installed, do you want to install it? [Y|n] ")

        if response in ("N", "n", "no", "No", "NO"):
            logger.error(f"Package {package} is not installed, run 'pip install {package}' to install it")
            sys.exit(1)
        elif response in ("Y", "y", "yes", "Yes", "YES", ""):
            subprocess.run(shlex.split(f"pip install {package}"))
            logger.info(f"Package {package} installed, run me again!")
            sys.exit(0)
        else:
            response = None


try:
    from clinner.command import Type, command
    from clinner.run import Main
except Exception:
    request_install_requirement("clinner")

try:
    import jinja2

    templates = jinja2.Environment(loader=jinja2.FileSystemLoader("."), trim_blocks=True, lstrip_blocks=True)
except Exception:
    request_install_requirement("jinja2")


@command(
    command_type=Type.PYTHON,
    args=(
        (("-p", "--production"), {"help": "Build production image", "action": "store_true"}),
        (("--cache-from",), {"help": "Use an specific docker cache"}),
    ),
    parser_opts={"help": "Build docker image"},
)
def build(*args, **kwargs):
    context = {
        "labels": ['maintainer="José Antonio Perdiguero López <perdy@perdy.io>"'],
        "project": {
            "image": "python:3.9-slim",
            "path": APP_PATH,
            "files": ["setup.cfg"],
        },
        "app": {
            "path": "src",
            "packages": {
                "runtime": ["libpq-dev"],
                "build": ["build-essential"],
            },
            "requirements": ["pyproject.toml"],
        },
        "test": {"path": "tests"},
        "logs": {"path": "logs"},
        "production": kwargs["production"],
    }

    # Try to add lock files
    if os.path.isfile("poetry.lock"):
        context["app"]["requirements"].append("poetry.lock")

    dockerfile = templates.get_template("Dockerfile.j2").render(**context)
    logger.debug("---- Dockerfile ----\n%s\n--------------------", dockerfile)
    tag = f"-t {kwargs['tag']}"
    cache_from = f"--cache-from {kwargs['cache_from']}" if kwargs["cache_from"] else ""
    subprocess.run(shlex.split(f"docker build {cache_from} {tag} -f- .") + list(args), input=dockerfile.encode("utf-8"))


@command(command_type=Type.PYTHON, parser_opts={"help": "Clean directory"})
def clean(*args, **kwargs):
    if os.getuid() != 0:
        logger.error("It is necessary to call clean with sudo")
        return None

    for path in (".pytest_cache", ".coverage", "test-results", "logs"):
        try:
            if os.path.isfile(path):
                os.remove(path)
            else:
                shutil.rmtree(path)
            logger.info("Removed successfully: %s", path)
        except Exception:
            logger.error("Cannot remove: %s", path)


@command(
    command_type=Type.SHELL,
    args=(
        (("-a", "--docker-args"), {"help": "Arguments to be passed to docker", "action": "append", "default": None}),
        (("--isolated",), {"help": "Run the service without the rest of the stack", "action": "store_true"}),
    ),
    parser_opts={"help": "Run command through entrypoint"},
)
def run(*args, **kwargs) -> List[List[str]]:
    name = f"--name {kwargs['name']}" if kwargs["name"] else ""
    docker_args = " ".join(kwargs.get("docker_args") or [])
    if kwargs.get("isolated"):
        development = f"-it -v {LOCAL_PATH}:{APP_PATH}" if kwargs["development"] else ""
        cmds = [shlex.split(f"docker run {development} {docker_args} {name} {kwargs['tag']}") + list(args)]
    else:
        docker_file = f"-f {kwargs['docker_file']}" if kwargs["docker_file"] else ""
        cmds = [shlex.split(f"docker-compose {docker_file} run --service-ports {docker_args} {name} app") + list(args)]

    return cmds


@command(command_type=Type.SHELL, parser_opts={"help": "Black code formatting"})
def black(*args, **kwargs):
    kwargs["isolated"] = True
    return run("black", *args, **kwargs)


@command(command_type=Type.SHELL, parser_opts={"help": "Flake8 code analysis"})
def flake8(*args, **kwargs):
    kwargs["isolated"] = True
    return run("flake8", *args, **kwargs)


@command(command_type=Type.SHELL, parser_opts={"help": "Isort imports formatting"})
def isort(*args, **kwargs):
    kwargs["isolated"] = True
    return run("isort", *args, **kwargs)


@command(command_type=Type.SHELL, parser_opts={"help": "Run lint"})
def lint(*args, **kwargs) -> List[List[str]]:
    kwargs["isolated"] = True
    return black("--check", ".", **kwargs) + flake8(**kwargs) + isort("--check", "--diff", ".", **kwargs)


@command(command_type=Type.SHELL, parser_opts={"help": "Run unit tests"})
def unit_tests(*args, **kwargs) -> List[List[str]]:
    kwargs["isolated"] = True

    mark = "type_unit and not wip" if not kwargs["development"] else "type_unit"

    return run("pytest", "-m", mark, *args, **kwargs)


@command(command_type=Type.SHELL, parser_opts={"help": "Run integration tests"})
def integration_tests(*args, **kwargs) -> List[List[str]]:
    kwargs["docker_args"] = ["-e", "TESTING=true"]

    mark = "type_integration and not wip" if not kwargs["development"] else "type_integration"

    return run("pytest", "--no-cov", "-m", mark, *args, **kwargs)


class Make(Main):
    def add_arguments(self, parser):
        parser.add_argument("--development", help="Run in development mode", action="store_true")
        parser.add_argument("-t", "--tag", help="Docker image tag", default=f"{IMAGE}:latest")
        parser.add_argument("-f", "--docker-file", help="Docker or docker-compose file")
        parser.add_argument("--name", help="Container name", default="")


if __name__ == "__main__":
    sys.exit(Make().run())
