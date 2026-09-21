#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define DEFAULT_PORT 9907
#define LOCK_PATH "/var/lib/endpoint3/maintenance.lock"

static int write_all(int fd, const char *buffer, size_t length)
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

static void respond(int client, int status, const char *reason, const char *body)
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
        (void)write_all(client, header, (size_t)header_length);
        (void)write_all(client, body, strlen(body));
    }
}

static void handle_request(int client)
{
    char request[2048];
    char method[16] = "";
    char path[1024] = "";
    ssize_t length = read(client, request, sizeof(request) - 1);

    if (length <= 0) {
        return;
    }

    request[length] = '\0';
    if (sscanf(request, "%15s %1023s", method, path) != 2) {
        respond(client, 400, "Bad Request", "{\"error\":\"BAD_REQUEST\"}");
        return;
    }

    if (strcmp(method, "GET") != 0) {
        respond(
            client,
            405,
            "Method Not Allowed",
            "{\"error\":\"METHOD_NOT_ALLOWED\"}");
        return;
    }

    if (strncmp(path, "/health", strlen("/health")) == 0) {
        respond(client, 200, "OK", "{\"service\":\"endpoint3\",\"ok\":true}");
        return;
    }

    /*
     * Open the lock rather than using stat(2). This makes the relevant file
     * access visible when the participant traces the service.
     */
    int lock_fd = open(LOCK_PATH, O_RDONLY);
    if (lock_fd >= 0) {
        close(lock_fd);
        respond(
            client,
            503,
            "Service Unavailable",
            "{\"service\":\"endpoint3\",\"ok\":false,"
            "\"error\":\"MAINTENANCE\"}");
        return;
    }

    respond(client, 200, "OK", "{\"service\":\"endpoint3\",\"ok\":true}");
}

int main(int argc, char **argv)
{
    int port = DEFAULT_PORT;
    int server;
    int reuse = 1;
    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
    };

    if (argc == 3 && strcmp(argv[1], "-p") == 0) {
        port = atoi(argv[2]);
    }
    if (port < 1 || port > 65535) {
        fprintf(stderr, "invalid port\n");
        return EXIT_FAILURE;
    }
    address.sin_port = htons((unsigned short)port);

    signal(SIGPIPE, SIG_IGN);

    server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) {
        perror("socket");
        return EXIT_FAILURE;
    }
    (void)setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    if (bind(server, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind");
        close(server);
        return EXIT_FAILURE;
    }
    if (listen(server, 16) < 0) {
        perror("listen");
        close(server);
        return EXIT_FAILURE;
    }

    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("accept");
            break;
        }
        handle_request(client);
        close(client);
    }

    close(server);
    return EXIT_FAILURE;
}
