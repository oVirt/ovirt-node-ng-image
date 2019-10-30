#!/usr/bin/python3

import argparse
from pylorax.treeinfo import TreeInfo


def main():
    parser = argparse.ArgumentParser(prog="mktreeinfo")
    parser.add_argument("--product", help="product name", required=True)
    parser.add_argument("--version", help="product version", required=True)
    parser.add_argument("--variant", help="variant id", required=True)
    parser.add_argument("--arch", help="architecture", required=True)
    parser.add_argument("FILENAME", help="output filename")
    args = parser.parse_args()

    ti = TreeInfo(args.product, args.version, args.variant, args.arch)
    images = {"initrd": "images/pxeboot/initrd.img",
              "kernel": "images/pxeboot/vmlinuz",
              "product.img": "images/product.img"}
    ti.add_section("images-{}".format(args.arch), images)
    ti.write(args.FILENAME)


if __name__ == "__main__":
    main()
