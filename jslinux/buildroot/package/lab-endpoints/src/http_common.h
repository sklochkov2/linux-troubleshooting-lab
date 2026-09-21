#ifndef LAB_HTTP_COMMON_H
#define LAB_HTTP_COMMON_H

#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int lab_write_all(int fd, const char *buffer, size_t length)
{
    while (length > 0) {
        ssize_t written = write(fd, buffer, length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        buffer += written;
        length -= (size_t)written;
    }
    return 0;
}

static void lab_respond(
    int client,
    int status,
    const char *reason,
    const char *body)
{
    char header[512];
    int header_length = snprintf(
        header,
        sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n",
        status,
        reason,
        strlen(body));

    if (header_length > 0 && (size_t)header_length < sizeof(header)) {
        (void)lab_write_all(client, header, (size_t)header_length);
        (void)lab_write_all(client, body, strlen(body));
    }
}

static int lab_listen(const char *address_text, unsigned short port)
{
    int server;
    int reuse = 1;
    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_port = htons(port),
    };

    if (inet_pton(AF_INET, address_text, &address.sin_addr) != 1) {
        return -1;
    }
    signal(SIGPIPE, SIG_IGN);
    server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) {
        return -1;
    }
    (void)setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        listen(server, 16) < 0) {
        close(server);
        return -1;
    }
    return server;
}

static int lab_read_path(int client, char *path, size_t path_size)
{
    char request[2048];
    char method[16] = "";
    ssize_t length = read(client, request, sizeof(request) - 1);

    if (length <= 0) {
        return -1;
    }
    request[length] = '\0';
    if (sscanf(request, "%15s %1023s", method, path) != 2 ||
        strcmp(method, "GET") != 0 ||
        path_size < 1024) {
        return -1;
    }
    return 0;
}

static int lab_is_health(const char *path)
{
    return strcmp(path, "/health") == 0 ||
        strncmp(path, "/health?", strlen("/health?")) == 0;
}

#endif
