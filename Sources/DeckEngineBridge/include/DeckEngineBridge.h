#pragma once
// UTF-8 JSON response owned by Rust. Release every response with od_engine_free.
char *od_engine_request(const char *path, const char *request);
void od_engine_free(char *response);

#include <stdint.h>
#include <stdbool.h>
uint64_t od_shortcut_advance(void);
bool od_shortcut_is_current(uint64_t ticket);

char *od_layout_request(const char *request);
