#!/usr/bin/python3
"""Dual-EVG UDP command driver.

Supported commands:
    - Software trigger request
    - Reboot request
"""

import struct
import socket
from enum import IntEnum
import logging
from time import time
from argparse import ArgumentParser

# Protocol constants
PACKET_MAGIC = 0xBD018426
HEADER_SIZE = 12
REBOOT_SEQUENCE = (1, 100, 10000)
MAX_RECV_SIZE = 1024

logger = logging.getLogger(__name__)


class Command(IntEnum):
    SW_TRIG_EVENT_GEN_0 = 0x00001100
    SW_TRIG_EVENT_GEN_1 = 0x00001101
    REBOOT = 0x00001F00


class EvgCom:
    """Simple interface to send UDP commands to a Dual-EVG device."""

    def __init__(
        self,
        ip: str,
        port: int = 58762,
        timeout: float = 1.5
    ):
        self.ip = ip
        self.port = port
        self.nonce = int(time())
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(timeout)

    def _build_packet(self, cmd: int, args: int | list[int]) -> bytes:
        """Assemble a binary packet according to the EVG protocol."""
        if isinstance(args, int):
            args = [args]
        elif not isinstance(args, list):
            raise TypeError(
                f"args must be int or list[int], got {type(args).__name__}")

        payload = struct.pack(
            f"<III{len(args)}I", PACKET_MAGIC, self.nonce, cmd, *args)
        self.nonce += 1
        return payload

    def _send(self, packet: bytes) -> bytes:
        """Send a packet and return the response data."""
        self.sock.sendto(packet, (self.ip, self.port))
        logger.info(f"Sent {packet.hex()} to {self.ip}:{self.port}")
        data, _ = self.sock.recvfrom(MAX_RECV_SIZE)
        return data

    def _verify_header(self, response: bytes, packet: bytes) -> None:
        expected = packet[:HEADER_SIZE]
        response = response[:HEADER_SIZE]
        assert response == expected, \
            f"header mismatch: expected {expected.hex()}, got {response.hex()}"

    def reboot(self):
        """Send the reboot request sequence."""
        for i, arg in enumerate(REBOOT_SEQUENCE):
            packet = self._build_packet(Command.REBOOT, arg)
            is_last = i == len(REBOOT_SEQUENCE) - 1

            if is_last:
                # Final command triggers immediate reboot
                self.sock.sendto(packet, (self.ip, self.port))
                logger.info("Reboot command sent, device will not respond")
                return

            response = self._send(packet)
            self._verify_header(response, packet)

    def sw_trigger(self, event: int, generator: int):
        """Send a software trigger request.

        Args:
            event:     Event code in the range [1, 255].
            generator: Generator index, 0 or 1.
        """
        try:
            cmd = Command(Command.SW_TRIG_EVENT_GEN_0 + generator)
        except ValueError:
            raise ValueError(f"Invalid generator index: {generator}")

        packet = self._build_packet(cmd, event)
        response = self._send(packet)

        self._verify_header(response, packet)


def parse_args() -> ArgumentParser:
    parser = ArgumentParser(prog="devg", description=__doc__)
    parser.add_argument(
        "-v", "--verbose", action="store_true")
    parser.add_argument(
        "--ip", default="192.168.1.150", help="IP address (%(default)s).")
    for i in range(2):
        parser.add_argument(
            f"-e{i}", f"--event-gen{i}", dest=f"event_g{i}",
            type=int, default=0, help=f"Event value for generator {i}.",
        )
    parser.add_argument(
        "-r", "--reboot", action="store_true", help="Reboot Dual-EVG."
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.WARNING,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    com = EvgCom(ip=args.ip)

    for gen in range(2):
        event = getattr(args, f"event_g{gen}")
        if event:
            com.sw_trigger(event=event, generator=gen)

    if args.reboot:
        com.reboot()
