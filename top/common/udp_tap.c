/* udp_tap.c: tap_alloc() for badger's ethernet_model.c, without a tap device.
 *
 * ethernet_model.c moves Ethernet frames between the simulated GMII and the
 * file descriptor tap_alloc() returns. Here that descriptor is one end of a
 * socketpair, and a thread on the other end bridges a UDP port on localhost:
 * a datagram from a client becomes an Ethernet/IPv4/UDP frame to the FPGA's
 * LEEP port, and a UDP frame from the FPGA becomes a datagram back to the
 * client (the frame's destination port is the client's port). So a host
 * client (leep://127.0.0.1:<port>) reaches badger in the simulated top with no
 * tap device and no root access, as in CI. Other frames from the FPGA (none
 * are expected) are dropped.
 *
 * TOPSIM_UDP_PORT sets the local port (default 8030). The FPGA's MAC and IP
 * are marble_zest_frame.sv's defaults.
 */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "tap_alloc.h"

static const uint8_t fpga_mac[6] = {0x00, 0x10, 0x5a, 0xd1, 0x55, 0xb2};
static const uint8_t fpga_ip[4] = {192, 168, 7, 123};
static const uint8_t host_mac[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0x01};
static const uint8_t host_ip[4] = {192, 168, 7, 1};
#define FPGA_PORT 803  /* LEEP */
#define HDR_LEN (14 + 20 + 8)

static int sim_fd;  /* our end of the socketpair: frames to and from the GMII */
static int udp_fd;  /* the UDP port on localhost */

static uint16_t ip_checksum(const uint8_t *h, int len)
{
	uint32_t sum = 0;
	for (int i = 0; i < len; i += 2) sum += (h[i] << 8) | h[i+1];
	while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
	return ~sum;
}

static void put16(uint8_t *p, unsigned v) { p[0] = v >> 8; p[1] = v; }
static unsigned get16(const uint8_t *p) { return (p[0] << 8) | p[1]; }

/* Ethernet/IPv4/UDP frame to the FPGA, from host port sport */
static int to_frame(uint8_t *f, const uint8_t *payload, int n, unsigned sport)
{
	static unsigned ident = 0;
	uint8_t *ip = f + 14, *udp = ip + 20;
	memcpy(f, fpga_mac, 6);
	memcpy(f + 6, host_mac, 6);
	put16(f + 12, 0x0800);
	memset(ip, 0, 20);
	ip[0] = 0x45;
	put16(ip + 2, 20 + 8 + n);
	put16(ip + 4, ident++);
	ip[8] = 64;  /* TTL */
	ip[9] = 17;  /* UDP */
	memcpy(ip + 12, host_ip, 4);
	memcpy(ip + 16, fpga_ip, 4);
	put16(ip + 10, ip_checksum(ip, 20));
	put16(udp, sport);
	put16(udp + 2, FPGA_PORT);
	put16(udp + 4, 8 + n);
	put16(udp + 6, 0);  /* no UDP checksum */
	memcpy(udp + 8, payload, n);
	return HDR_LEN + n;
}

static void *bridge(void *arg)
{
	(void) arg;
	uint8_t buf[2048], frame[2048];
	struct pollfd p[2] = {{udp_fd, POLLIN, 0}, {sim_fd, POLLIN, 0}};
	for (;;) {
		if (poll(p, 2, -1) < 0) continue;
		if (p[0].revents & POLLIN) {
			struct sockaddr_in client;
			socklen_t cl = sizeof client;
			ssize_t n = recvfrom(udp_fd, buf, 1472, 0, (struct sockaddr *) &client, &cl);
			if (n >= 0) {
				int len = to_frame(frame, buf, n, ntohs(client.sin_port));
				if (send(sim_fd, frame, len, 0) < 0) perror("udp_tap: send to simulation");
			}
		}
		if (p[1].revents & POLLIN) {
			ssize_t n = recv(sim_fd, frame, sizeof frame, 0);
			const uint8_t *ip = frame + 14, *udp = ip + 20;
			if (n < HDR_LEN || get16(frame + 12) != 0x0800 || (ip[0] & 0x0f) != 5 || ip[9] != 17)
				continue;
			int len = get16(udp + 4) - 8;
			if (len < 0 || HDR_LEN + len > n) continue;
			struct sockaddr_in client = {0};
			client.sin_family = AF_INET;
			client.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
			client.sin_port = htons(get16(udp + 2));
			if (sendto(udp_fd, udp + 8, len, 0, (struct sockaddr *) &client, sizeof client) < 0)
				perror("udp_tap: send to client");
		}
	}
	return NULL;
}

int tap_alloc(char *dev)
{
	int sv[2];
	const char *ps = getenv("TOPSIM_UDP_PORT");
	int port = ps ? atoi(ps) : 8030;
	struct sockaddr_in a = {0};
	pthread_t th;

	if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sv) < 0) return -1;
	sim_fd = sv[1];
	if ((udp_fd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) return -1;
	a.sin_family = AF_INET;
	a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	a.sin_port = htons(port);
	if (bind(udp_fd, (struct sockaddr *) &a, sizeof a) < 0) return -1;
	if (pthread_create(&th, NULL, bridge, NULL) != 0) return -1;
	pthread_detach(th);
	snprintf(dev, 20, "udp:%d", port);
	fprintf(stderr, "udp_tap: leep://127.0.0.1:%d reaches the simulated FPGA\n", port);
	return sv[0];
}
