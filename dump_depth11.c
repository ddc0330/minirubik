#define SOLVER_HOST_VERIFY
#define SOLVER_ITERATIVE
#define SOLVER_STATE_MAJOR

/*
 * Rename solver.c's own main(), because this helper provides
 * a different main().
 */
#define main solver_original_main
#include "solver.c"
#undef main

static void print_state(const state_t *state)
{
    for (int i = 0; i < 7; ++i)
        putchar('1' + state->p[i]);

    for (int i = 0; i < 7; ++i)
        putchar('1' + state->o[i]);

    putchar('\n');
}

int main(void)
{
    uint8_t diameter;

    /*
     * Rebuild the same host-side structures used by the exhaustive
     * Stage 3 verification.
     */
    build_coordinate_tables();

    if (!build_heuristic_tables()) {
        fprintf(stderr, "failed to build heuristic tables\n");
        return 1;
    }

    uint8_t *distance = build_table(&diameter);

    if (!distance) {
        fprintf(stderr, "failed to build BFS distance table\n");
        return 1;
    }

    unsigned count = 0;

    for (uint32_t rank = 0; rank < STATES; ++rank) {
        if (distance[rank] != MAX_DEPTH)
            continue;

        state_t state;
        unrank_state(rank, &state);
        print_state(&state);
        ++count;
    }

    free(distance);

    fprintf(stderr, "distance-%u states: %u\n",
            MAX_DEPTH, count);

    return count == 2644 ? 0 : 1;
}