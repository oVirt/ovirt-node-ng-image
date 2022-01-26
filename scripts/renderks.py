#!/usr/bin/python3

import os
import yaml
import argparse
from jinja2 import FileSystemLoader, Environment


def main():
    parser = argparse.ArgumentParser(prog="renderks")
    parser.add_argument("--data-dir", default="./data",
                        help="jinja2 environment directory")
    parser.add_argument("DISTRO", help="distro name")
    args = parser.parse_args()

    with open(os.path.join(args.data_dir, "distro-defs.yml")) as f:
        data = yaml.load(f)[args.DISTRO]

    env = Environment(loader=FileSystemLoader(searchpath=args.data_dir))
    template = env.get_template("ovirt-node-ng-image.j2")
    print(template.render(data=data))


if __name__ == '__main__':
    main()
