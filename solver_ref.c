#include <stdint.h>

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    MOVES = 9,
    MAX_DEPTH = 11
};

#define SOLVER_STATE_MAJOR
#include "solver_tables.inc"

typedef struct {
    uint16_t p, o;
    uint8_t next_move;
    uint8_t previous_face;
    uint8_t incoming_move;
} search_frame_t;

/*
 * volatile prevents GCC from simply treating the test vector as
 * compile-time known input.
 */
static const volatile char cube_input[15] = "21345671111111";

volatile int solution_length;
uint8_t solution_path[MAX_DEPTH];
volatile int verification_result;


static uint8_t coordinate_heuristic(uint16_t p, uint16_t o)
{
    return perm_dist[p] > ori_dist[o] ?
           perm_dist[p] : ori_dist[o];
}


static void rank_input(const volatile char *input,
                       uint16_t *p_out, uint16_t *o_out)
{
    uint32_t p = 0;
    uint32_t o = 0;

    for (uint32_t i = 0; i < CUBIES; ++i) {
        uint32_t smaller = 0;
        uint8_t here = (uint8_t)input[i];

        for (uint32_t j = i + 1; j < CUBIES; ++j)
            if ((uint8_t)input[j] < here)
                ++smaller;

        p = p * (CUBIES - i) + smaller;
    }

    for (uint32_t i = 0; i < 6; ++i)
        o = o * 3U + ((uint8_t)input[CUBIES + i] - (uint8_t)'1');

    *p_out = (uint16_t)p;
    *o_out = (uint16_t)o;
}


static int ida_search_iterative(uint16_t p, uint16_t o,
                                uint8_t bound, uint8_t *path)
{
    search_frame_t frames[MAX_DEPTH + 1];
    uint8_t depth = 0;

    frames[0] = (search_frame_t){p, o, 0, 3, 0};

    if (p == 0 && o == 0)
        return 1;

    if (bound == 0)
        return 0;

    for (;;) {
        search_frame_t *frame = &frames[depth];

        if (frame->next_move == MOVES) {
            if (depth == 0)
                return 0;

            --depth;
            continue;
        }

        uint8_t move = frame->next_move;
        uint8_t face = (uint8_t)(move / 3U);

        if (face == frame->previous_face) {
            frame->next_move = (uint8_t)(move + 3U);
            continue;
        }

        ++frame->next_move;

        uint16_t next_p = perm_next[frame->p][move];
        uint16_t next_o = ori_next[frame->o][move];

        uint8_t child_remaining =
            (uint8_t)(bound - depth - 1U);

        if (coordinate_heuristic(next_p, next_o) >
            child_remaining)
            continue;

        if (next_p == 0 && next_o == 0) {
            for (uint8_t i = 0; i < depth; ++i)
                path[i] = frames[i + 1U].incoming_move;

            path[depth] = move;
            return 1;
        }

        if (child_remaining == 0)
            continue;

        ++depth;

        frames[depth] =
            (search_frame_t){next_p, next_o, 0, face, move};
    }
}


static int solve_coordinates(uint16_t p, uint16_t o,
                             uint8_t *path)
{
    for (uint8_t bound = coordinate_heuristic(p, o);
         bound <= MAX_DEPTH;
         ++bound) {

        if (ida_search_iterative(p, o, bound, path))
            return bound;
    }

    return -1;
}


static int verify_solution(uint16_t p, uint16_t o,
                           const uint8_t *path, int length)
{
    if (length < 0)
        return 0;

    for (int i = 0; i < length; ++i) {
        uint8_t move = path[i];

        if (move >= MOVES)
            return 0;

        p = perm_next[p][move];
        o = ori_next[o][move];
    }

    return p == 0 && o == 0;
}


__attribute__((noreturn))
void _start(void)
{
    uint16_t p, o;

    rank_input(cube_input, &p, &o);

    int length = solve_coordinates(p, o, solution_path);

    solution_length = length;
    verification_result =
        verify_solution(p, o, solution_path, length);

    /* Ripes exit */
    __asm__ volatile (
        "li a7, 10\n"
        "ecall\n"
    );

    __builtin_unreachable();
}