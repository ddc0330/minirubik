#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    STATES = PERMUTATIONS * ORIENTATIONS,
    MOVES = 9,
    MAX_DEPTH = 11
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

/*@ predicate valid_state(state_t *state) =
      (\forall integer i; 0 <= i < CUBIES ==>
         state->p[i] < CUBIES && state->o[i] < 3) &&
      (\forall integer i, j; 0 <= i < j < CUBIES ==>
         state->p[i] != state->p[j]) &&
      (state->o[0] + state->o[1] + state->o[2] + state->o[3] +
       state->o[4] + state->o[5] + state->o[6]) % 3 == 0;
 */

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};
static const uint8_t inverse_move[MOVES] = {2, 1, 0, 5, 4, 3, 8, 7, 6};
/* Each destination takes a cubie from source[face][destination]. */
static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

/* Coordinate transitions for all nine moves; initialized before use. */
static uint16_t perm_next[MOVES][PERMUTATIONS];
static uint16_t ori_next[MOVES][ORIENTATIONS];
static uint8_t perm_dist[PERMUTATIONS];
static uint8_t ori_dist[ORIENTATIONS];

/* The three quarter-turns preserve the fixed front-upper-left corner. */
/*@ requires face < 3;
    assigns \nothing;
    ensures \forall integer i; 0 <= i < CUBIES ==>
              \result.p[i] == state.p[source[face][i]];
    ensures \forall integer i; 0 <= i < CUBIES ==>
              \result.o[i] == (state.o[source[face][i]] + twist[face][i]) % 3;
 */
static state_t quarter_turn(state_t state, uint8_t face)
{
    state_t result;
    /*@ loop invariant 0 <= i <= CUBIES;
        loop invariant \forall integer j; 0 <= j < i ==>
          result.p[j] == state.p[source[face][j]];
        loop invariant \forall integer j; 0 <= j < i ==>
          result.o[j] == (state.o[source[face][j]] + twist[face][j]) % 3;
        loop assigns i, result.p[0..6], result.o[0..6];
        loop variant CUBIES - i;
    */
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t from = source[face][i];
        result.p[i] = state.p[from];
        result.o[i] = (uint8_t) ((state.o[from] + twist[face][i]) % 3U);
    }
    return result;
}

static state_t apply_move(state_t state, uint8_t move)
{
    uint8_t turns = (uint8_t) (move % 3U + 1U);
    for (uint8_t i = 0; i < turns; ++i)
        state = quarter_turn(state, (uint8_t) (move / 3U));
    return state;
}

/*@ requires \valid_read(state);
    requires \forall integer i; 0 <= i < CUBIES ==>
      0 <= state->p[i] < CUBIES;
    requires \forall integer i, j; 0 <= i < j < CUBIES ==>
      state->p[i] != state->p[j];
    requires \forall integer i; 0 <= i < CUBIES ==>
      0 <= state->o[i] < 3;
    assigns \nothing;
    ensures \result < STATES;
 */
static uint32_t rank_state(const state_t *state)
{
    uint32_t p = 0, o = 0;
    /*@ loop invariant 0 <= i <= CUBIES;
        loop invariant (i == 0 ==> p == 0) && (i == 1 ==> p <= 6) &&
          (i == 2 ==> p <= 41) && (i == 3 ==> p <= 209) &&
          (i == 4 ==> p <= 839) && (i == 5 ==> p <= 2519) &&
          (i >= 6 ==> p <= 5039);
        loop assigns i, p;
        loop variant CUBIES - i;
     */
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        /*@ loop invariant i + 1 <= j <= CUBIES;
            loop invariant smaller <= j - i - 1;
            loop assigns j, smaller;
            loop variant CUBIES - j;
         */
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j)
            if (state->p[j] < state->p[i])
                ++smaller;
        p = p * (CUBIES - i) + smaller;
    }
    /*@ loop invariant 0 <= i <= 6;
        loop invariant (i == 0 ==> o == 0) && (i == 1 ==> o < 3) &&
          (i == 2 ==> o < 9) && (i == 3 ==> o < 27) &&
          (i == 4 ==> o < 81) && (i == 5 ==> o < 243) &&
          (i == 6 ==> o < 729);
        loop assigns i, o;
        loop variant 6 - i;
     */
    for (uint8_t i = 0; i < 6; ++i)
        o = o * 3U + state->o[i];
    return p * ORIENTATIONS + o;
}

/*@ requires \valid(state); requires rank < STATES; assigns *state; */
static void unrank_state(uint32_t rank, state_t *state)
{
    uint8_t available[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t p = rank / ORIENTATIONS, o = rank % ORIENTATIONS, f = 720;
    uint8_t sum = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t q = (uint8_t) (p / f);
        p %= f;
        state->p[i] = available[q];
        for (uint8_t j = q; j + 1U < CUBIES - i; ++j)
            available[j] = available[j + 1U];
        if (i < 5)
            f /= 6U - i;
    }
    for (uint8_t i = 6; i-- > 0;) {
        state->o[i] = (uint8_t) (o % 3U);
        sum = (uint8_t) (sum + state->o[i]);
        o /= 3U;
    }
    state->o[6] = (uint8_t) ((3U - sum % 3U) % 3U);
}

/*@ requires \valid_read(state);
    requires \initialized(&state->p[0..6]) && \initialized(&state->o[0..6]);
    assigns \nothing;
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->p[i] < CUBIES && state->o[i] < 3;
    ensures \result != 0 ==> \forall integer i, j; 0 <= i < j < CUBIES ==>
      state->p[i] != state->p[j];
    ensures \result != 0 ==>
      (state->o[0] + state->o[1] + state->o[2] + state->o[3] +
       state->o[4] + state->o[5] + state->o[6]) % 3 == 0;
    ensures complete: valid_state(state) ==> \result != 0;
 */
static int valid(const state_t *state)
{
    uint8_t sum = 0;
    /*@ loop invariant 0 <= i <= CUBIES;
        loop invariant sum <= 2 * i;
        loop invariant sum == (i > 0 ? state->o[0] : 0) +
          (i > 1 ? state->o[1] : 0) + (i > 2 ? state->o[2] : 0) +
          (i > 3 ? state->o[3] : 0) + (i > 4 ? state->o[4] : 0) +
          (i > 5 ? state->o[5] : 0) + (i > 6 ? state->o[6] : 0);
        loop invariant \forall integer j; 0 <= j < i ==>
          state->p[j] < CUBIES && state->o[j] < 3;
        loop invariant \forall integer j, k; 0 <= j < k < i ==>
          state->p[j] != state->p[k];
        loop assigns i, sum;
        loop variant CUBIES - i;
    */
    for (uint8_t i = 0; i < CUBIES; ++i) {
        if (state->p[i] >= CUBIES || state->o[i] >= 3)
            return 0;
        /*@ loop invariant 0 <= j <= i;
            loop invariant \forall integer k; 0 <= k < j ==>
              state->p[k] != state->p[i];
            loop assigns j;
            loop variant i - j;
        */
        for (uint8_t j = 0; j < i; ++j)
            if (state->p[j] == state->p[i])
                return 0;
        sum = (uint8_t) (sum + state->o[i]);
    }
    return sum % 3U == 0;
}

static void build_coordinate_tables(void)
{
    state_t state;
    for (uint16_t p = 0; p < PERMUTATIONS; ++p) {
        unrank_state((uint32_t) p * ORIENTATIONS, &state);
        for (uint8_t move = 0; move < MOVES; ++move) {
            state_t next = apply_move(state, move);
            perm_next[move][p] =
                (uint16_t) (rank_state(&next) / ORIENTATIONS);
        }
    }
    for (uint16_t o = 0; o < ORIENTATIONS; ++o) {
        unrank_state(o, &state);
        for (uint8_t move = 0; move < MOVES; ++move) {
            state_t next = apply_move(state, move);
            ori_next[move][o] =
                (uint16_t) (rank_state(&next) % ORIENTATIONS);
        }
    }
}

/* Shared scratch queue on the stack, sized for the larger abstraction.
 * It is needed only during initialization, never during the search.
 */
static int build_heuristic_tables(void)
{
    uint16_t queue[PERMUTATIONS];
    uint16_t head = 0, tail = 1;
    memset(perm_dist, UINT8_MAX, sizeof perm_dist);
    perm_dist[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint16_t here = queue[head++];
        for (uint8_t move = 0; move < MOVES; ++move) {
            uint16_t there = perm_next[move][here];
            if (perm_dist[there] == UINT8_MAX) {
                perm_dist[there] = (uint8_t) (perm_dist[here] + 1U);
                queue[tail++] = there;
            }
        }
    }
    if (tail != PERMUTATIONS)
        return 0;

    head = 0;
    tail = 1;
    memset(ori_dist, UINT8_MAX, sizeof ori_dist);
    ori_dist[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint16_t here = queue[head++];
        for (uint8_t move = 0; move < MOVES; ++move) {
            uint16_t there = ori_next[move][here];
            if (ori_dist[there] == UINT8_MAX) {
                ori_dist[there] = (uint8_t) (ori_dist[here] + 1U);
                queue[tail++] = there;
            }
        }
    }
    return tail == ORIENTATIONS;
}

static int check_heuristic_tables(void)
{
    if (perm_dist[0] != 0 || ori_dist[0] != 0)
        return 0;
    for (uint16_t p = 0; p < PERMUTATIONS; ++p) {
        if (perm_dist[p] == UINT8_MAX || (p != 0 && perm_dist[p] == 0))
            return 0;
        for (uint8_t move = 0; move < MOVES; ++move) {
            uint8_t next = perm_dist[perm_next[move][p]];
            if ((unsigned) next > (unsigned) perm_dist[p] + 1U ||
                (unsigned) perm_dist[p] > (unsigned) next + 1U)
                return 0;
        }
    }
    for (uint16_t o = 0; o < ORIENTATIONS; ++o) {
        if (ori_dist[o] == UINT8_MAX || (o != 0 && ori_dist[o] == 0))
            return 0;
        for (uint8_t move = 0; move < MOVES; ++move) {
            uint8_t next = ori_dist[ori_next[move][o]];
            if ((unsigned) next > (unsigned) ori_dist[o] + 1U ||
                (unsigned) ori_dist[o] > (unsigned) next + 1U)
                return 0;
        }
    }
    return 1;
}

static uint8_t coordinate_heuristic(uint16_t p, uint16_t o)
{
    return perm_dist[p] > ori_dist[o] ? perm_dist[p] : ori_dist[o];
}

/* Return success only when a solution fits in the remaining depth.
 * path is written on successful unwinding, so failed branches leave it alone.
 */
static int ida_search(uint16_t p, uint16_t o, uint8_t remaining,
                      uint8_t previous_face, uint8_t depth, uint8_t *path)
{
    if (coordinate_heuristic(p, o) > remaining)
        return 0;
    if (p == 0 && o == 0)
        return 1;
    if (remaining == 0)
        return 0;
    for (uint8_t move = 0; move < MOVES; ++move) {
        uint8_t face = (uint8_t) (move / 3U);
        if (face == previous_face)
            continue;
        if (ida_search(perm_next[move][p], ori_next[move][o],
                       (uint8_t) (remaining - 1U), face,
                       (uint8_t) (depth + 1U), path)) {
            path[depth] = move;
            return 1;
        }
    }
    return 0;
}

/* The first successful bound is optimal because the heuristic is admissible.
 * Same-face pairs can always be replaced by at most one move.
 */
static int solve_coordinates(uint16_t p, uint16_t o, uint8_t *path)
{
    for (uint8_t bound = coordinate_heuristic(p, o);
         bound <= MAX_DEPTH; ++bound) {
        if (ida_search(p, o, bound, 3, 0, path))
            return bound;
    }
    return -1;
}

static uint8_t *build_table(uint8_t *diameter)
{
    uint8_t *toward_solved = malloc(STATES);
    uint32_t *queue = malloc((size_t) STATES * sizeof *queue);
    uint16_t permutation[3][PERMUTATIONS], orientation[3][ORIENTATIONS];
    uint32_t head = 0, tail = 1, level_end = 1;
    state_t state;
    if (!toward_solved || !queue) {
        free(toward_solved);
        free(queue);
        return NULL;
    }
    for (uint16_t rank = 0; rank < PERMUTATIONS; ++rank) {
        unrank_state((uint32_t) rank * ORIENTATIONS, &state);
        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            permutation[face][rank] =
                (uint16_t) (rank_state(&next) / ORIENTATIONS);
        }
    }
    for (uint16_t rank = 0; rank < ORIENTATIONS; ++rank) {
        unrank_state(rank, &state);
        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            orientation[face][rank] =
                (uint16_t) (rank_state(&next) % ORIENTATIONS);
        }
    }
    memset(toward_solved, UINT8_MAX, STATES);
    queue[0] = 0;
    toward_solved[0] = 0;
    *diameter = 0;
    while (head < tail) {
        if (head == level_end) {
            level_end = tail;
            ++*diameter;
        }
        uint32_t here = queue[head++];
        uint16_t p = (uint16_t) (here / ORIENTATIONS);
        uint16_t o = (uint16_t) (here % ORIENTATIONS);
        for (uint8_t face = 0; face < 3; ++face) {
            uint16_t next_p = p, next_o = o;
            for (uint8_t turn = 0; turn < 3; ++turn) {
                next_p = permutation[face][next_p];
                next_o = orientation[face][next_o];
                uint32_t there = (uint32_t) next_p * ORIENTATIONS + next_o;
                if (toward_solved[there] == UINT8_MAX) {
                    uint8_t move = (uint8_t) (face * 3U + turn);
                    toward_solved[there] = inverse_move[move];
                    queue[tail++] = there;
                }
            }
        }
    }
    free(queue);
    if (tail != STATES) {
        free(toward_solved);
        return NULL;
    }
    return toward_solved;
}

/*@ requires valid_read_string(input);
    requires \valid(state);
    assigns state->p[0..6], state->o[0..6];
    ensures \result != 0 ==> input[14] == '\0';
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->p[i] < CUBIES && state->o[i] < 3;
    ensures \result != 0 ==> \forall integer i, j; 0 <= i < j < CUBIES ==>
      state->p[i] != state->p[j];
    ensures \result != 0 ==>
      (state->o[0] + state->o[1] + state->o[2] + state->o[3] +
       state->o[4] + state->o[5] + state->o[6]) % 3 == 0;
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->p[i] == input[i] - '1';
    ensures \result != 0 ==> \forall integer i; 0 <= i < CUBIES ==>
      state->o[i] == input[i + CUBIES] - '1';
 */
static int parse_state(const char *input, state_t *state)
{
    /*@ loop invariant 0 <= i <= 14;
        loop invariant i <= strlen(input);
        loop invariant i <= 7 ==> \initialized(&state->p[0..i-1]);
        loop invariant i >= 7 ==> \initialized(&state->p[0..6]);
        loop invariant i >= 7 ==> \initialized(&state->o[0..i-8]);
        loop invariant \forall integer j; 0 <= j < i && j < CUBIES ==>
          state->p[j] == input[j] - '1';
        loop invariant \forall integer j; 0 <= j < i - CUBIES ==>
          state->o[j] == input[j + CUBIES] - '1';
        loop assigns i, state->p[0..6], state->o[0..6];
        loop variant 14 - i;
     */
    for (int i = 0; i < 14; ++i) {
        int limit = i < 7 ? 7 : 3;
        if (input[i] < '1' || input[i] > '0' + limit)
            return 0;
        (i < 7 ? state->p : state->o)[i % 7] = (uint8_t) (input[i] - '1');
    }
    return input[14] == '\0' && valid(state);
}

/* stdout is fully buffered off a terminal, so a write error surfaces at the
 * flush, not at the printf that queued the bytes. Every exit path that has
 * produced output goes through here.
 */
static int output_failed(void)
{
    return fflush(stdout) != 0 || ferror(stdout);
}

static int self_test(void)
{
    const state_t solved = {{0, 1, 2, 3, 4, 5, 6}, {0}};
    state_t state;
    for (uint8_t move = 0; move < MOVES; ++move) {
        state = solved;
        state = apply_move(state, move);
        state = apply_move(state, inverse_move[move]);
        if (memcmp(&solved, &state, sizeof solved))
            return 0;
    }
    for (uint32_t rank = 0; rank < STATES; ++rank) {
        unrank_state(rank, &state);
        if (!valid(&state) || rank_state(&state) != rank)
            return 0;
        uint16_t p = (uint16_t) (rank / ORIENTATIONS);
        uint16_t o = (uint16_t) (rank % ORIENTATIONS);
        for (uint8_t move = 0; move < MOVES; ++move) {
            uint16_t next_p = perm_next[move][p];
            uint16_t next_o = ori_next[move][o];
            if (next_p >= PERMUTATIONS || next_o >= ORIENTATIONS)
                return 0;
            if (perm_next[inverse_move[move]][next_p] != p ||
                ori_next[inverse_move[move]][next_o] != o)
                return 0;
            state_t next = apply_move(state, move);
            if (rank_state(&next) !=
                (uint32_t) next_p * ORIENTATIONS + next_o)
                return 0;
        }
    }
    return 1;
}

int main(int argc, char **argv)
{
    state_t state;
    uint8_t diameter;
    if (argc == 2 && !strcmp(argv[1], "--self-test")) {
        build_coordinate_tables();
        if (!build_heuristic_tables() || !check_heuristic_tables()) {
            fputs("heuristic table check failed\n", stderr);
            return 1;
        }
        if (!self_test()) {
            fputs("self-test failed\n", stderr);
            return 1;
        }
        uint8_t *table = build_table(&diameter);
        if (!table) {
            fputs("could not build complete state table\n", stderr);
            return 1;
        }
        free(table);
        if (diameter != 11) {
            fputs("BFS check failed\n", stderr);
            return 1;
        }
        puts("3674160 states; diameter 11");
        return output_failed();
    }
    if (argc != 2 || !parse_state(argv[1], &state)) {
        /* C99 5.1.2.2.1 lets argv[0] be null when argc is 0. */
        fprintf(stderr, "usage: %s PPPPPPPOOOOOOO\n",
                argc > 0 && argv[0] ? argv[0] : "solver");
        return 2;
    }
    build_coordinate_tables();
    if (!build_heuristic_tables()) {
        fputs("could not build complete heuristic tables\n", stderr);
        return 1;
    }
    uint8_t path[MAX_DEPTH];
    uint32_t rank = rank_state(&state);
    int length = solve_coordinates((uint16_t) (rank / ORIENTATIONS),
                                   (uint16_t) (rank % ORIENTATIONS), path);
    if (length < 0) {
        fputs("IDA* search failed\n", stderr);
        return 1;
    }
    /* Verify with the original cubie moves before emitting the solution. */
    for (int i = 0; i < length; ++i)
        state = apply_move(state, path[i]);
    if (rank_state(&state) != 0) {
        fputs("solution verification failed\n", stderr);
        return 1;
    }
    const char *separator = "";
    for (int i = 0; i < length; ++i) {
        printf("%s%s", separator, move_names[path[i]]);
        separator = " ";
    }
    putchar('\n');
    return output_failed();
}
