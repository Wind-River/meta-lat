/*
 * mttysplit - A simple tty splitter to send intputs and outputs
 * to multiple ptys at the same time using stdin/stdout/stderr
 *
 * Copyright (c) 2020 Wind River Systems, Inc. Jason Wessel
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <signal.h>
#include <fcntl.h>
#include <pty.h>
#include <errno.h>

#ifndef VDISABLE
#ifdef _POSIX_VDISABLE
#define VDISABLE _POSIX_VDISABLE
#else
#define VDISABLE 0377
#endif
#endif

#define MAX_DEV 10
int fd_file;
int cfd[MAX_DEV]; /* Client FD */
struct termios orig_term[MAX_DEV];
int devices = 0;

fd_set master_rds;
int nsockhandle = 0;
static char *prog;
int USE_STDOUT = 1;
int USE_FILE = 0;

int STDOUT;
int STDIN;

static void restore_term(void) {
	int i;

	for(i = 0; i < devices; i++) {
		tcsetattr(cfd[i], TCSADRAIN, &orig_term[i]);
		tcdrain(cfd[i]);
	}
}

static void cleanup(int exit_code) {
	restore_term();
	exit(exit_code);
}

static void usage()
{
	printf("Usage:\n");
	printf("%s [-s] [-d device ] [ -d device] cmd [args...]\n\n", prog);
	printf("  Arugment info:\n");
	printf("     -d <device> A tty device to send input/ouput\n");
	printf("     -f <log-file> A file to save output\n");
	printf("     -s          Suppress input/ouput on original terminal\n");
	cleanup(1);
}

static void fd_setup(int fd) {
	int flags;

	flags = fcntl(fd, F_GETFL);
	if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
		printf("Failed to set O_NONBLOCK\n");
		cleanup(1);
	}
	FD_SET(fd, &master_rds);
}

static void select_init() {
	int i;
	struct termios cur_term;

	for (i = 0; i < devices; i++) {
		if (cfd[i] >= nsockhandle) {
			nsockhandle = cfd[i] + 1;
		}
		fd_setup(cfd[i]);
		memcpy(&cur_term, &orig_term[i], sizeof(struct termios));
		cur_term.c_iflag &= ~(IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL);
		cur_term.c_iflag &= ~(IXON|IXOFF);
		cur_term.c_oflag &= ~(OPOST);
		cur_term.c_lflag &= ~(ECHO|ECHONL|ICANON|ISIG|IEXTEN);
		cur_term.c_cflag &= ~(CSIZE|PARENB);
		cur_term.c_cflag |= CS8;
		cur_term.c_cc[VLNEXT] = VDISABLE;
		cur_term.c_cc[VMIN] = 1;
		cur_term.c_cc[VTIME] = 0;
		tcsetattr(cfd[i], TCSADRAIN, &cur_term);
	}
}

int pfd[2];
int pty_fd;

static void fork_start(char **argv) {
	char readchar[2];
	int pty_cmd_fd;
	struct termios start_term;
	int i;

	if (tcgetattr(0, &start_term) < 0) {
		for (i = 0; i < devices; i++)
			if (tcgetattr(cfd[i], &start_term) < 0)
				memset(&start_term, 0, sizeof(struct termios));
			else
				break;
	}

	if (openpty(&pty_fd, &pty_cmd_fd, NULL, &start_term, NULL) < 0) {
		perror("Failed openpty");
		cleanup(1);
	}
	if (pty_fd < 0 || pty_cmd_fd < 0) {
		perror("Pty setup failed");
		cleanup(1);
	}
	if (USE_STDOUT)
		fd_setup(STDIN);
	fd_setup(pty_fd);
	if (pty_fd >= nsockhandle) {
		nsockhandle = pty_fd + 1;
	}
	if (pipe(pfd)) {
		printf("Error: pipe open\n");
		cleanup(1);
	}
	int child = fork();
	if (child < 0) {
		perror("Failed fork");
		cleanup(1);
	}
	if (child) {
		signal(SIGCHLD, SIG_IGN);
		close(pfd[1]);
		close(pty_fd);
		for (i = 0; i < devices; i++)
			close(cfd[i]);
		/* Wait for a character on the pipe */
		if (read(pfd[0], readchar, 1) != 1) {
			printf("Error: starting server\n");
			cleanup(1);
		}
		if (USE_FILE)
			close(fd_file);
		signal(SIGCHLD, SIG_DFL);
		dup2(pty_cmd_fd, fileno(stdin));
		dup2(pty_cmd_fd, fileno(stdout));
		dup2(pty_cmd_fd, fileno(stderr));
		execvp(*argv, argv);
		cleanup(1);
	}
	/* Child is the server from here out */
	close(pfd[0]);
	close(pty_cmd_fd);
	/* Go full on daemon */
	int pid = fork();
	if (pid < 0)
		cleanup(1);
	if (pid) {
		exit(0);
	}
	select_init();
	if (setsid() < 0) {
		perror("Running setid()");
		cleanup(1);
	}
}

static ssize_t _write(int fd, void *buf, size_t count) {
	ssize_t n;
	while ((n = write(fd, buf, count)) < 1) {
		if (errno == EAGAIN) {
			usleep(1);
			continue;
		}
		return n;
	}
	return n;
}

static void data_loop(char **argv) {
	fd_set rds;
	int ret;
	int i, j;
	char buf[2];
	
	FD_ZERO(&master_rds);
	fork_start(argv);
	atexit(restore_term);
	/* Start the master program running */
	if (_write(pfd[1], "w", 1) < 1) {
		printf("Error Failed client initiation\n");
		cleanup(1);
	}
	while (1) {
		memcpy(&rds, &master_rds, sizeof(master_rds));
		ret = select(nsockhandle, &rds, NULL, NULL, NULL);
		if (ret < 0)
			return;
		for (i = 0; i < devices && ret > 0; i++) {
			if (FD_ISSET(cfd[i], &rds)) {
				if (read(cfd[i], buf, 1) < 0)
					cleanup(1);
				if (_write(pty_fd, buf, 1) < 1)
					cleanup(1);
				ret--;
			}
		}
		if (ret > 0 && FD_ISSET(STDIN, &rds)) {
			if (read(STDIN, buf, 1) < 0)
				cleanup(1);
			if (_write(pty_fd, buf, 1) < 1)
				cleanup(1);
			ret--;
		}
		if (ret > 0 && FD_ISSET(pty_fd, &rds)) {
			if (read(pty_fd, buf, 1) < 0)
				cleanup(1);
			if (USE_STDOUT)
				if (_write(STDOUT, buf, 1) < 1)
					cleanup(1);
			if (USE_FILE)
				if (_write(fd_file, buf, 1) < 1)
					cleanup(1);
			for (j = 0; j < devices; j++) {
				if (_write(cfd[j], buf, 1) < 1)
					cleanup(1);
			}
			ret--;
		}
	}
}

int main(int argc, char **argv)
{
	int i;
	prog=argv[0];
	argv++;
	argc--;

	if (argc < 1) {
		usage();
	}
	STDOUT = fileno(stdout);
	STDIN = fileno(stdin);
	for (i = 0; i < argc; i++) {
		if (strcmp("-h", argv[i]) == 0) {
			usage();
		}else if (strcmp("-s", argv[i]) == 0) {
			USE_STDOUT = 0;
		}else if (strcmp("-f", argv[i]) == 0) {
			USE_FILE = 1;
			i++;
			if (i >= argc) {
				printf("Error not enough arguments\n");
				cleanup(1);
			}
			fd_file = open(argv[i], O_CREAT|O_APPEND|O_RDWR, O_RDWR);
			if (fd_file < 0) {
				printf("Error failed to open file: %s\n", argv[i]);
				cleanup(1);
			}
		} else if (strcmp("-d", argv[i]) == 0) {
			i++;
			if (i >= argc) {
				printf("Error not enough arguments\n");
				cleanup(1);
			}
			cfd[devices] = open(argv[i], O_RDWR);
			if (cfd[devices] < 0) {
				printf("Error failed to open device: %s\n", argv[i]);
				cleanup(1);
			}
			tcgetattr(cfd[devices], &orig_term[devices]);
			devices++;
			if (devices == MAX_DEV) {
				printf("Error too many devices specified\n");
				cleanup(1);
			}
		} else {
			break;
		}
	}
	argv += i;
	argc -= i;
	data_loop(argv);
	return 0;
}
