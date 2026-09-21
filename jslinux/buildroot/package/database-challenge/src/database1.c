#include "http_common.h"

#include <sys/wait.h>

#define SERVICE_PORT 9006
#define EXPECTED_MATCHED_ROWS 1
#define EXPECTED_DATASET_ROWS 100000
#define MAX_HEALTHY_ROWS_READ 100

struct query_metrics {
    long long elapsed_microseconds;
    long long matched_rows;
    long long rows_read;
    long long dataset_rows;
};

static const char *workload_command =
    "/usr/bin/mysql --batch --skip-column-names "
    "--protocol=socket --socket=/run/mysql/mysql.sock "
    "--user=lab --database=lab --execute=\""
    "SET @started=NOW(6);"
    "SELECT SQL_NO_CACHE COUNT(*) FROM events "
    "WHERE lookup_key='needle';"
    "SELECT TIMESTAMPDIFF(MICROSECOND,@started,NOW(6));"
    "SHOW SESSION STATUS LIKE 'Rows_read';"
    "SELECT COUNT(*) FROM events"
    "\" 2>/dev/null";

static int read_integer_line(FILE *pipe, long long *value)
{
    char line[256];
    char *end;
    long long parsed;

    if (fgets(line, sizeof(line), pipe) == NULL) {
        return -1;
    }
    errno = 0;
    parsed = strtoll(line, &end, 10);
    if (errno != 0 || end == line) {
        return -1;
    }
    *value = parsed;
    return 0;
}

static int run_workload(struct query_metrics *metrics)
{
    char status_line[256];
    char *separator;
    FILE *pipe = popen(workload_command, "r");
    int status;

    if (pipe == NULL) {
        return -1;
    }

    if (read_integer_line(pipe, &metrics->matched_rows) != 0 ||
        read_integer_line(pipe, &metrics->elapsed_microseconds) != 0 ||
        fgets(status_line, sizeof(status_line), pipe) == NULL) {
        (void)pclose(pipe);
        return -1;
    }
    separator = strchr(status_line, '\t');
    if (separator == NULL) {
        (void)pclose(pipe);
        return -1;
    }
    metrics->rows_read = strtoll(separator + 1, NULL, 10);
    if (read_integer_line(pipe, &metrics->dataset_rows) != 0) {
        (void)pclose(pipe);
        return -1;
    }

    status = pclose(pipe);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

static void handle_workload(int client)
{
    struct query_metrics metrics = {0};
    char body[384];
    int healthy;
    long long elapsed_ms;

    if (run_workload(&metrics) != 0) {
        lab_respond(
            client,
            500,
            "Internal Server Error",
            "{\"service\":\"database1\",\"ok\":false,"
            "\"error\":\"QUERY_FAILED\"}");
        return;
    }

    elapsed_ms = (metrics.elapsed_microseconds + 999) / 1000;
    healthy =
        metrics.matched_rows == EXPECTED_MATCHED_ROWS &&
        metrics.dataset_rows == EXPECTED_DATASET_ROWS &&
        metrics.rows_read <= MAX_HEALTHY_ROWS_READ;
    snprintf(
        body,
        sizeof(body),
        "{\"service\":\"database1\",\"ok\":%s,"
        "\"elapsed_ms\":%lld,\"matched_rows\":%lld,"
        "\"rows_read\":%lld,\"dataset_rows\":%lld}",
        healthy ? "true" : "false",
        elapsed_ms,
        metrics.matched_rows,
        metrics.rows_read,
        metrics.dataset_rows);
    lab_respond(
        client,
        healthy ? 200 : 503,
        healthy ? "OK" : "Service Unavailable",
        body);
}

int main(void)
{
    int server = lab_listen("127.0.0.1", SERVICE_PORT);

    if (server < 0) {
        perror("database1 listen");
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
        } else {
            handle_workload(client);
        }
        close(client);
    }
}
