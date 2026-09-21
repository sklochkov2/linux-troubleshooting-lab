#include "http_common.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>

#define SERVICE_PORT 9002
#define LOG_DIRECTORY "/var/log/endpoint2/logs"

int main(void)
{
    unsigned long counter = 0;
    int server = lab_listen("127.0.0.1", SERVICE_PORT);

    if (server < 0) {
        perror("endpoint2 listen");
        return EXIT_FAILURE;
    }

    for (;;) {
        int client = accept(server, NULL, NULL);
        char path[1024];

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
                "{\"service\":\"endpoint2\",\"ok\":true}");
        } else {
            char filename[512];
            char line[1200];
            int log_fd;

            snprintf(
                filename,
                sizeof(filename),
                LOG_DIRECTORY "/request-%ld-%lu.log",
                (long)time(NULL),
                counter++);
            log_fd = open(filename, O_WRONLY | O_CREAT | O_EXCL, 0644);
            if (log_fd < 0) {
                lab_respond(
                    client,
                    500,
                    "Internal Server Error",
                    "{\"service\":\"endpoint2\",\"ok\":false,"
                    "\"error\":\"WRITE_FAILED\"}");
            } else {
                int length = snprintf(
                    line,
                    sizeof(line),
                    "path=%s time=%ld\n",
                    path,
                    (long)time(NULL));
                if (length > 0) {
                    (void)lab_write_all(log_fd, line, (size_t)length);
                }
                close(log_fd);
                lab_respond(
                    client,
                    200,
                    "OK",
                    "{\"service\":\"endpoint2\",\"ok\":true}");
            }
        }
        close(client);
    }
}
