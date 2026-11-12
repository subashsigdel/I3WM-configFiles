/*
 * swipe.c - tiny touchpad swipe -> i3 workspace switcher.
 *
 * Talks to libinput directly (no Python, no text parsing) and sleeps in
 * poll() until the touchpad sends something.
 *
 * Build:  gcc -O2 -s -o swipe swipe.c $(pkg-config --cflags --libs libinput libudev)
 * Needs:  your user in the `input` group.
 */
#include <fcntl.h>
#include <libinput.h>
#include <libudev.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <unistd.h>

#define FINGERS   3     /* how many fingers the swipe needs */
#define THRESHOLD 50.0  /* how far you must swipe to trigger */

/* fingers move left / right */
static char *const SWIPE_LEFT_CMD[]  = {"i3-msg", "-q", "workspace", "prev_on_output", NULL};
static char *const SWIPE_RIGHT_CMD[] = {"i3-msg", "-q", "workspace", "next_on_output", NULL};

extern char **environ;

static int open_restricted(const char *path, int flags, void *data) {
    (void)data;
    int fd = open(path, flags | O_CLOEXEC);
    return fd < 0 ? -1 : fd;
}

static void close_restricted(int fd, void *data) {
    (void)data;
    close(fd);
}

static const struct libinput_interface iface = {
    .open_restricted = open_restricted,
    .close_restricted = close_restricted,
};

static void run(char *const argv[]) {
    pid_t pid;
    posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ);
}

int main(void) {
    signal(SIGCHLD, SIG_IGN); /* finished i3-msg processes are cleaned up automatically */

    struct udev *udev = udev_new();
    struct libinput *li = libinput_udev_create_context(&iface, NULL, udev);
    if (!li || libinput_udev_assign_seat(li, "seat0") != 0) {
        fprintf(stderr, "swipe: cannot open input devices (are you in the 'input' group?)\n");
        return 1;
    }

    struct pollfd pfd = {.fd = libinput_get_fd(li), .events = POLLIN};
    double dx = 0, dy = 0;

    while (poll(&pfd, 1, -1) >= 0) {
        libinput_dispatch(li);
        struct libinput_event *ev;
        while ((ev = libinput_get_event(li))) {
            enum libinput_event_type type = libinput_event_get_type(ev);

            if (type == LIBINPUT_EVENT_GESTURE_SWIPE_BEGIN ||
                type == LIBINPUT_EVENT_GESTURE_SWIPE_UPDATE ||
                type == LIBINPUT_EVENT_GESTURE_SWIPE_END) {
                struct libinput_event_gesture *g = libinput_event_get_gesture_event(ev);

                if (libinput_event_gesture_get_finger_count(g) == FINGERS) {
                    if (type == LIBINPUT_EVENT_GESTURE_SWIPE_BEGIN) {
                        dx = dy = 0;
                    } else if (type == LIBINPUT_EVENT_GESTURE_SWIPE_UPDATE) {
                        dx += libinput_event_gesture_get_dx(g);
                        dy += libinput_event_gesture_get_dy(g);
                    } else if (!libinput_event_gesture_get_cancelled(g) &&
                               fabs(dx) > THRESHOLD && fabs(dx) > fabs(dy)) {
                        run(dx < 0 ? SWIPE_LEFT_CMD : SWIPE_RIGHT_CMD);
                    }
                }
            }
            libinput_event_destroy(ev);
        }
    }
    return 0;
}
