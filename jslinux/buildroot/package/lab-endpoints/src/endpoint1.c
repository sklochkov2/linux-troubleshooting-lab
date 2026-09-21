#include "http_common.h"

#include <netdb.h>

#define SERVICE_PORT 9001
#define UPSTREAM_PORT 8081
#define UPSTREAM_HOST "upstream.lab"

static int check_upstream(char *resolved, size_t resolved_size)
{
    struct addrinfo hints = {
        .ai_family = AF_INET,
        .ai_socktype = SOCK_STREAM,
    };
    struct addrinfo *addresses = NULL;
    int connection = -1;
    int ok = 0;

    if (getaddrinfo(UPSTREAM_HOST, "8081", &hints, &addresses) != 0 ||
        addresses == NULL) {
        snprintf(resolved, resolved_size, "unresolved");
        return 0;
    }

    (void)inet_ntop(
        AF_INET,
        &((struct sockaddr_in *)addresses->ai_addr)->sin_addr,
        resolved,
        resolved_size);
    connection = socket(AF_INET, SOCK_STREAM, 0);
    if (connection >= 0 &&
        connect(connection, addresses->ai_addr, addresses->ai_addrlen) == 0) {
        static const char request[] =
            "GET / HTTP/1.0\r\nHost: " UPSTREAM_HOST "\r\n\r\n";
        char response[128];
        if (lab_write_all(connection, request, sizeof(request) - 1) == 0 &&
            read(connection, response, sizeof(response)) > 0) {
            ok = 1;
        }
    }

    if (connection >= 0) {
        close(connection);
    }
    freeaddrinfo(addresses);
    return ok;
}

static int run_upstream(void)
{
    int server = lab_listen("127.0.0.2", UPSTREAM_PORT);
    if (server < 0) {
        perror("endpoint1 upstream listen");
        return EXIT_FAILURE;
    }

    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client >= 0) {
            char request[512];
            static const char response[] =
                "HTTP/1.0 200 OK\r\n"
                "Content-Length: 2\r\n"
                "Connection: close\r\n\r\nOK";
            (void)read(client, request, sizeof(request));
            (void)lab_write_all(client, response, sizeof(response) - 1);
            close(client);
        }
    }
}

int main(int argc, char **argv)
{
    int server;

    if (argc == 2 && strcmp(argv[1], "--upstream") == 0) {
        return run_upstream();
    }

    server = lab_listen("127.0.0.1", SERVICE_PORT);
    if (server < 0) {
        perror("endpoint1 listen");
        return EXIT_FAILURE;
    }

    for (;;) {
        int client = accept(server, NULL, NULL);
        char path[1024];
        char resolved[INET_ADDRSTRLEN] = "unresolved";

        if (client < 0) {
            continue;
        }
        if (lab_read_path(client, path, sizeof(path)) != 0) {
            lab_respond(client, 400, "Bad Request", "{\"error\":\"BAD_REQUEST\"}");
        } else if (lab_is_health(path)) {
            lab_respond(
                client,
                200,
                "OK",
                "{\"service\":\"endpoint1\",\"ok\":true}");
        } else if (check_upstream(resolved, sizeof(resolved))) {
            char body[256];
            snprintf(
                body,
                sizeof(body),
                "{\"service\":\"endpoint1\",\"host\":\"%s\","
                "\"resolved_ip\":\"%s\",\"ok\":true}",
                UPSTREAM_HOST,
                resolved);
            lab_respond(client, 200, "OK", body);
        } else {
            char body[256];
            snprintf(
                body,
                sizeof(body),
                "{\"service\":\"endpoint1\",\"host\":\"%s\","
                "\"resolved_ip\":\"%s\",\"ok\":false,"
                "\"error\":\"UPSTREAM_UNREACHABLE\"}",
                UPSTREAM_HOST,
                resolved);
            lab_respond(client, 503, "Service Unavailable", body);
        }
        close(client);
    }
}
