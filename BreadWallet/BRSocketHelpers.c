//
//  BRSocketHelpers.c
//  BreadWallet
//
//  Created by Samuel Sutch on 2/17/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

#include "BRSocketHelpers.h"
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <stdlib.h>

int bw_nbioify(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return flags;
    flags = flags &~ O_NONBLOCK;
    return fcntl(fd, F_SETFL, flags);
}

struct bw_select_result bw_select(struct bw_select_request request) {
    fd_set read_fds, write_fds, err_fds;
    FD_ZERO(&read_fds);
    FD_ZERO(&write_fds);
    FD_ZERO(&err_fds);
    int max_fd = 0;
    // copy requested file descriptors from request to fd_sets
    for (int i = 0; i < request.read_fd_len; i++) {
        if (request.read_fds[i] > max_fd) {
            max_fd = request.read_fds[i];
        }
        FD_SET(request.read_fds[i], &read_fds);
    }
    for (int i = 0; i < request.write_fd_len; i++) {
        if (request.write_fds[i] > max_fd) {
            max_fd = request.write_fds[i];
        }
        FD_SET(request.write_fds[i], &write_fds);
    }
    
    struct bw_select_result result;
    
    // initiate a select
    int activity = select(max_fd + 1, &read_fds, &write_fds, &err_fds, NULL);
    if (activity < 0 && errno != EINTR) {
        result.error = errno;
        perror("select");
        return result;
    }
    // indicate to the caller which file descriptors are ready for reading
    for (int i = 0; i < request.read_fd_len; i++) {
        if (FD_ISSET(request.read_fds[i], &read_fds)) {
            result.read_fd_len += 1;
            result.read_fds = (int *)realloc(result.read_fds, result.read_fd_len * sizeof(int));
            result.read_fds[result.read_fd_len - 1] = request.read_fds[i];
        }
        // ... which ones are erroring
        if (FD_ISSET(request.read_fds[i], &err_fds)) {
            result.error_fd_len += 1;
            result.error_fds = (int *)realloc(result.error_fds, result.error_fd_len * sizeof(int));
            result.error_fds[result.error_fd_len - 1] = request.read_fds[i];
        }
    }
    // ... and which ones are ready for writing
    for (int i = 0; i < request.write_fd_len; i++) {
        if (FD_ISSET(request.write_fds[i], &read_fds)) {
            result.write_fd_len += 1;
            result.write_fds = (int *)realloc(result.write_fds, result.write_fd_len * sizeof(int));
            result.write_fds[result.write_fd_len - 1] = request.write_fds[i];
        }
        if (FD_ISSET(request.write_fds[i], &err_fds)) {
            result.error_fd_len += 1;
            result.error_fds = (int *)realloc(result.error_fds, result.error_fd_len * sizeof(int));
            result.error_fds[result.error_fd_len - 1] = request.write_fds[i];
        }
    }
    return result;
}
