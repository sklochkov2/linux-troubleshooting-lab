#include "http_common.h"

#include <fcntl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <time.h>

#define SERVICE_PORT 9134
#define STRESS_DIRECTORY "/var/lib/endpoint4/stress"
#define MAX_HELD_FILES 128
#define REQUEST_GUARDS 8
#define ACCEPT_RESERVE 1

static int held_files[MAX_HELD_FILES];
static size_t held_count;
static unsigned long request_counter;

static void saturate_descriptors(void)
{
    size_t index;

    (void)mkdir("/var/lib/endpoint4", 0755);
    (void)mkdir(STRESS_DIRECTORY, 0755);
    for (index = 0; index < MAX_HELD_FILES; index++) {
        char path[256];
        int fd;

        snprintf(path, sizeof(path), STRESS_DIRECTORY "/fill-%zu.bin", index);
        fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) {
            break;
        }
        held_files[held_count++] = fd;
    }

    for (index = 0;
         index < ACCEPT_RESERVE + REQUEST_GUARDS && held_count > 0;
         index++) {
        close(held_files[--held_count]);
    }
}

static void handle_request(int client)
{
    char path[1024];
    int guards[REQUEST_GUARDS];
    size_t guard_count = 0;

    if (lab_read_path(client, path, sizeof(path)) != 0) {
        lab_respond(client, 400, "Bad Request", "{\"error\":\"BAD_REQUEST\"}");
        return;
    }
    if (lab_is_health(path)) {
        lab_respond(
            client,
            200,
            "OK",
            "{\"service\":\"endpoint4\",\"ok\":true}");
        return;
    }

    while (guard_count < REQUEST_GUARDS) {
        int fd = open("/dev/null", O_RDONLY);
        if (fd < 0) {
            break;
        }
        guards[guard_count++] = fd;
    }

    {
        char filename[256];
        int request_fd;
        snprintf(
            filename,
            sizeof(filename),
            STRESS_DIRECTORY "/request-%ld-%lu.bin",
            (long)time(NULL),
            request_counter++);
        request_fd = open(filename, O_WRONLY | O_CREAT | O_EXCL, 0644);
        if (request_fd < 0) {
            lab_respond(
                client,
                503,
                "Service Unavailable",
                "{\"service\":\"endpoint4\",\"ok\":false,"
                "\"error\":\"EMFILE_TOO_MANY_OPEN_FILES\"}");
        } else {
            close(request_fd);
            lab_respond(
                client,
                200,
                "OK",
                "{\"service\":\"endpoint4\",\"ok\":true}");
        }
    }

    while (guard_count > 0) {
        close(guards[--guard_count]);
    }
}

int main(void)
{
    int server = lab_listen("127.0.0.1", SERVICE_PORT);

    if (server < 0) {
        perror("endpoint4 listen");
        return EXIT_FAILURE;
    }
    saturate_descriptors();

    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client >= 0) {
            handle_request(client);
            close(client);
        }
    }
}
