    .equ RENDER, 0

    .equ MAX_DEPTH, 11
    
    .equ MOVES, 9

    /* search_frame_t layout */
    .equ FRAME_P,        0
    .equ FRAME_O,        2
    .equ FRAME_NEXT,     4
    .equ FRAME_PREV,     5
    .equ FRAME_INCOMING, 6
    .equ FRAME_SIZE,     8

    .equ FRAME_COUNT,    12
    .equ FRAMES_BYTES,   96

    /* ida_search_iterative stack frame */
    .equ STACK_FRAMES,   0       /* 96 bytes: offsets 0..95 */
    .equ STACK_PATH,     96      /* 11 bytes: offsets 96..106 */
    .equ STACK_PAD,      107

    .equ SAVE_S0,        108
    .equ SAVE_S1,        112
    .equ SAVE_S2,        116
    .equ SAVE_S3,        120
    .equ SAVE_RA,        124

    .equ STACK_SIZE,     128


    /* ============================================================
     * Read-only data
     * ============================================================ */

    .section .rodata
    .balign 1

    .globl cube_input
cube_input:
    .ascii "21345671111111"
cube_input_end:
    .byte 0

    .if (cube_input_end - cube_input) != 14
    .error "cube_input must contain exactly 14 characters"
    .endif


    /* ============================================================
     * Code
     * ============================================================ */

        .section .text
    .balign 4

    .globl _start
    .type _start, @function

_start:

    /* Rank input */
    la      a0, cube_input
    call    rank_input

    /* Solve */
    la      a2, solution_path
    call    solve_coordinates

    /* Save solution length */
    la      t0, solution_length
    sw      a0, 0(t0)

    /* Negative length means search failure */
    blt     a0, zero, .Lstart_verify_fail


    /*
     * Rank the original input again because solve_coordinates
     * is allowed to overwrite a0/a1.
     */

    la      a0, cube_input
    call    rank_input

    /* Replay solution */
    la      a2, solution_path

    la      t0, solution_length
    lw      a3, 0(t0)

    call    verify_solution

    /* Save verification result */
    la      t0, verification_result
    sw      a0, 0(t0)

    j       .Lstart_exit


.Lstart_verify_fail:

    la      t0, verification_result
    sw      zero, 0(t0)


.Lstart_exit:

    li      a7, 10
    ecall

    .size _start, . - _start


    /* These tables are provided by solver_tables.S */
    .extern perm_next
    .extern ori_next
    .extern perm_dist
    .extern ori_dist


    /* ============================================================
     * rank_input
     *
     * a0 = pointer to 14-character input
     *
     * returns:
     *   a0 = permutation coordinate p
     *   a1 = orientation coordinate o
     *
     * Input:
     *   PPPPPPPOOOOOOO
     * ============================================================ */

    .globl rank_input
    .type rank_input, @function

rank_input:

    /* ------------------------------------------------------------
     * Permutation rank
     *
     * For every position i:
     *
     * smaller = number of later cubies smaller than p[i]
     * rank = rank * (7 - i) + smaller
     *
     * ASCII digits can be compared directly because their order
     * is the same as the numeric order.
     * ------------------------------------------------------------ */

    li      t0, 0              /* i */
    li      t1, 0              /* permutation rank */

.Lrank_p_outer:
    li      t3, 7
    bgeu    t0, t3, .Lrank_p_done

    add     t3, a0, t0
    lbu     t2, 0(t3)          /* input[i] */

    li      t4, 0              /* smaller */
    addi    t5, t0, 1          /* j = i + 1 */

.Lrank_p_inner:
    li      t3, 7
    bgeu    t5, t3, .Lrank_p_count_done

    add     t6, a0, t5
    lbu     t6, 0(t6)          /* input[j] */

    bgeu    t6, t2, .Lrank_p_no_inc

    addi    t4, t4, 1          /* smaller++ */

.Lrank_p_no_inc:
    addi    t5, t5, 1
    j       .Lrank_p_inner


.Lrank_p_count_done:

    /*
     * rank *= (7 - i)
     *
     * No MUL instruction because only RV32I is allowed.
     * Ranking is done only once, so repeated addition is fine here.
     */

    li      t5, 7
    sub     t5, t5, t0        /* multiplier = 7 - i */

    li      t6, 0

.Lrank_p_mul:
    beqz    t5, .Lrank_p_mul_done

    add     t6, t6, t1
    addi    t5, t5, -1

    j       .Lrank_p_mul


.Lrank_p_mul_done:

    add     t1, t6, t4        /* rank += smaller */

    addi    t0, t0, 1
    j       .Lrank_p_outer


.Lrank_p_done:

    /* ------------------------------------------------------------
     * Orientation rank
     *
     * Only the first six orientations are stored:
     *
     * o = o * 3 + orientation[i]
     *
     * input orientation characters are '1'..'3',
     * therefore subtract ASCII '1' (49).
     * ------------------------------------------------------------ */

    li      t2, 0              /* orientation rank */
    addi    t3, a0, 7          /* first orientation character */
    li      t0, 0              /* i */

.Lrank_o_loop:
    li      t4, 6
    bgeu    t0, t4, .Lrank_done

    lbu     t4, 0(t3)
    addi    t4, t4, -49        /* '1' -> 0, '2' -> 1, '3' -> 2 */

    /*
     * o * 3 = o * 2 + o
     */
    slli    t5, t2, 1
    add     t2, t5, t2
    add     t2, t2, t4

    addi    t3, t3, 1
    addi    t0, t0, 1

    j       .Lrank_o_loop


.Lrank_done:

    mv      a0, t1             /* return p */
    mv      a1, t2             /* return o */

    ret

    .size rank_input, . - rank_input


    /* ============================================================
     * next_coordinates
     *
     * a0 = p
     * a1 = o
     * a2 = move (0..8)
     *
     * returns:
     *   a0 = next_p
     *   a1 = next_o
     *
     * Tables are state-major:
     *
     *   perm_next[p][move]
     *   ori_next[o][move]
     *
     * uint16_t entry => 2 bytes
     * ============================================================ */

    .globl next_coordinates
    .type next_coordinates, @function

next_coordinates:

    /*
     * perm_next byte offset:
     *
     * (p * 9 + move) * 2
     * = p * 18 + move * 2
     *
     * p * 18 = p * 16 + p * 2
     */

    slli    t0, a0, 4          /* p * 16 */
    slli    t1, a0, 1          /* p * 2 */
    add     t0, t0, t1         /* p * 18 */

    slli    t2, a2, 1          /* move * 2 */
    add     t0, t0, t2

    la      t1, perm_next
    add     t0, t0, t1

    lhu     t3, 0(t0)          /* next_p */


    /*
     * ori_next byte offset:
     *
     * (o * 9 + move) * 2
     */

    slli    t0, a1, 4          /* o * 16 */
    slli    t1, a1, 1          /* o * 2 */
    add     t0, t0, t1         /* o * 18 */

    slli    t2, a2, 1          /* move * 2 */
    add     t0, t0, t2

    la      t1, ori_next
    add     t0, t0, t1

    lhu     a1, 0(t0)          /* next_o */

    mv      a0, t3             /* next_p */

    ret

    .size next_coordinates, . - next_coordinates


    /* ============================================================
     * coordinate_heuristic
     *
     * a0 = p
     * a1 = o
     *
     * returns:
     *
     * a0 = max(perm_dist[p], ori_dist[o])
     * ============================================================ */

    .globl coordinate_heuristic
    .type coordinate_heuristic, @function

coordinate_heuristic:

    /* perm_dist[p] */

    la      t0, perm_dist
    add     t0, t0, a0
    lbu     t1, 0(t0)


    /* ori_dist[o] */

    la      t0, ori_dist
    add     t0, t0, a1
    lbu     t2, 0(t0)


    /* max(t1, t2) */

    bgeu    t1, t2, .Lheuristic_perm

    mv      a0, t2
    ret


.Lheuristic_perm:

    mv      a0, t1
    ret

    .size coordinate_heuristic, . - coordinate_heuristic

    /* ============================================================
     * ida_search_iterative
     *
     * a0 = start p
     * a1 = start o
     * a2 = bound
     * a3 = path buffer
     *
     * return:
     *   a0 = 1 found
     *   a0 = 0 not found
     * ============================================================ */

    .globl ida_search_iterative
    .type ida_search_iterative, @function

ida_search_iterative:

    addi    sp, sp, -STACK_SIZE

    sw      s0, SAVE_S0(sp)
    sw      s1, SAVE_S1(sp)
    sw      s2, SAVE_S2(sp)
    sw      s3, SAVE_S3(sp)
    sw      ra, SAVE_RA(sp)

    mv      s0, sp             /* frames base */
    mv      s1, a3             /* solution path */
    mv      s2, a2             /* bound */
    li      s3, 0              /* depth */


    /* frames[0] = {p, o, 0, 3, 0} */

    sh      a0, FRAME_P(s0)
    sh      a1, FRAME_O(s0)
    sb      zero, FRAME_NEXT(s0)

    li      t0, 3
    sb      t0, FRAME_PREV(s0)

    sb      zero, FRAME_INCOMING(s0)


    /* solved root */

    or      t0, a0, a1
    beqz    t0, .Lida_success_root

    /* no moves allowed */

    beqz    s2, .Lida_fail


.Lida_loop:

    /*
     * frame = &frames[depth]
     *
     * FRAME_SIZE = 8
     */

    slli    t0, s3, 3
    add     t0, s0, t0


    /* move = frame->next_move */

    lbu     t1, FRAME_NEXT(t0)

    li      t2, MOVES
    beq     t1, t2, .Lida_exhausted


    /*
     * face = move / 3
     *
     * move 0..2 -> face 0
     * move 3..5 -> face 1
     * move 6..8 -> face 2
     *
     * Avoid DIV.
     */

    li      t2, 3
    bltu    t1, t2, .Lida_face0

    li      t2, 6
    bltu    t1, t2, .Lida_face1

    li      t2, 2
    j       .Lida_face_ready


.Lida_face0:
    li      t2, 0
    j       .Lida_face_ready


.Lida_face1:
    li      t2, 1


.Lida_face_ready:

    /*
     * same-face pruning
     */

    lbu     t3, FRAME_PREV(t0)
    beq     t2, t3, .Lida_same_face


    /*
     * Parent resumes from next move when child finishes.
     */

    addi    t3, t1, 1
    sb      t3, FRAME_NEXT(t0)


    /* current p / o */

    lhu     t3, FRAME_P(t0)    /* p */
    lhu     t4, FRAME_O(t0)    /* o */


    /* ------------------------------------------------------------
     * next_p = perm_next[p][move]
     *
     * byte offset = p * 18 + move * 2
     * ------------------------------------------------------------ */

    slli    t5, t3, 4          /* p * 16 */
    slli    t6, t3, 1          /* p * 2 */
    add     t5, t5, t6         /* p * 18 */

    slli    t6, t1, 1
    add     t5, t5, t6

    la      t6, perm_next
    add     t5, t5, t6

    lhu     t3, 0(t5)          /* next_p */


    /* ------------------------------------------------------------
     * next_o = ori_next[o][move]
     * ------------------------------------------------------------ */

    slli    t5, t4, 4
    slli    t6, t4, 1
    add     t5, t5, t6         /* o * 18 */

    slli    t6, t1, 1
    add     t5, t5, t6

    la      t6, ori_next
    add     t5, t5, t6

    lhu     t4, 0(t5)          /* next_o */


    /*
     * child_remaining = bound - depth - 1
     */

    sub     t5, s2, s3
    addi    t5, t5, -1


    /* ------------------------------------------------------------
     * heuristic pruning
     *
     * Instead of explicitly calculating max(),
     * prune if either component is > child_remaining.
     * ------------------------------------------------------------ */

    la      t6, perm_dist
    add     t6, t6, t3
    lbu     a4, 0(t6)

    bltu    t5, a4, .Lida_loop


    la      t6, ori_dist
    add     t6, t6, t4
    lbu     a5, 0(t6)

    bltu    t5, a5, .Lida_loop


    /*
     * solved?
     */

    or      t6, t3, t4
    beqz    t6, .Lida_found


    /*
     * Cannot go deeper.
     */

    beqz    t5, .Lida_loop


    /* ------------------------------------------------------------
     * Push child frame.
     * ------------------------------------------------------------ */

    addi    s3, s3, 1

    slli    t0, s3, 3
    add     t0, s0, t0

    sh      t3, FRAME_P(t0)
    sh      t4, FRAME_O(t0)

    sb      zero, FRAME_NEXT(t0)
    sb      t2, FRAME_PREV(t0)
    sb      t1, FRAME_INCOMING(t0)

    j       .Lida_loop


.Lida_same_face:

    /*
     * Skip all three moves belonging to this face.
     */

    addi    t1, t1, 3
    sb      t1, FRAME_NEXT(t0)

    j       .Lida_loop


.Lida_exhausted:

    /*
     * All moves at this depth have been tried.
     */

    beqz    s3, .Lida_fail

    addi    s3, s3, -1
    j       .Lida_loop


.Lida_found:

    /*
     * frames[1..depth] contain the moves used to descend.
     *
     * Copy them into path[0..depth-1].
     */

    li      t0, 0


.Lida_copy_path:

    bgeu    t0, s3, .Lida_copy_last

    addi    t2, t0, 1
    slli    t2, t2, 3
    add     t2, s0, t2

    lbu     t3, FRAME_INCOMING(t2)

    add     t4, s1, t0
    sb      t3, 0(t4)

    addi    t0, t0, 1
    j       .Lida_copy_path


.Lida_copy_last:

    /*
     * Current move solves the cube.
     */

    add     t4, s1, s3
    sb      t1, 0(t4)

    li      a0, 1
    j       .Lida_return


.Lida_success_root:

    li      a0, 1
    j       .Lida_return


.Lida_fail:

    li      a0, 0


.Lida_return:

    lw      ra, SAVE_RA(sp)
    lw      s3, SAVE_S3(sp)
    lw      s2, SAVE_S2(sp)
    lw      s1, SAVE_S1(sp)
    lw      s0, SAVE_S0(sp)

    addi    sp, sp, STACK_SIZE

    ret

    .size ida_search_iterative, . - ida_search_iterative
        /* ============================================================
     * solve_coordinates
     *
     * a0 = start p
     * a1 = start o
     * a2 = solution path buffer
     *
     * return:
     *   a0 = optimal solution length (0..11)
     *   a0 = -1 if search fails
     * ============================================================ */

    .globl solve_coordinates
    .type solve_coordinates, @function

solve_coordinates:

    addi    sp, sp, -32

    sw      s0, 12(sp)
    sw      s1, 16(sp)
    sw      s2, 20(sp)
    sw      s3, 24(sp)
    sw      ra, 28(sp)

    mv      s0, a0             /* start p */
    mv      s1, a1             /* start o */
    mv      s2, a2             /* path buffer */


    /* Initial bound = heuristic(p, o) */

    mv      a0, s0
    mv      a1, s1
    call    coordinate_heuristic

    mv      s3, a0             /* current bound */


.Lsolve_bound_loop:

    li      t0, MAX_DEPTH

    /* if bound > MAX_DEPTH -> fail */
    bltu    t0, s3, .Lsolve_fail


    /* ida_search_iterative(p, o, bound, path) */

    mv      a0, s0
    mv      a1, s1
    mv      a2, s3
    mv      a3, s2

    call    ida_search_iterative

    bnez    a0, .Lsolve_found

    addi    s3, s3, 1
    j       .Lsolve_bound_loop


.Lsolve_found:

    /* First successful bound is the optimal solution length. */

    mv      a0, s3
    j       .Lsolve_return


.Lsolve_fail:

    li      a0, -1


.Lsolve_return:

    lw      ra, 28(sp)
    lw      s3, 24(sp)
    lw      s2, 20(sp)
    lw      s1, 16(sp)
    lw      s0, 12(sp)

    addi    sp, sp, 32

    ret

        /* ============================================================
     * verify_solution
     *
     * Replay the returned path using coordinate transition tables.
     *
     * a0 = start p
     * a1 = start o
     * a2 = path
     * a3 = length
     *
     * return:
     *   a0 = 1  if final state is solved
     *   a0 = 0  otherwise
     * ============================================================ */

    .globl verify_solution
    .type verify_solution, @function

verify_solution:

    addi    sp, sp, -32

    sw      s0, 8(sp)
    sw      s1, 12(sp)
    sw      s2, 16(sp)
    sw      s3, 20(sp)
    sw      s4, 24(sp)
    sw      ra, 28(sp)

    mv      s0, a0             /* current p */
    mv      s1, a1             /* current o */
    mv      s2, a2             /* path */
    mv      s3, a3             /* length */
    li      s4, 0              /* i */


.Lverify_loop:

    bgeu    s4, s3, .Lverify_done

    /* move = path[i] */

    add     t0, s2, s4
    lbu     a2, 0(t0)

    /* move must be 0..8 */

    li      t1, MOVES
    bgeu    a2, t1, .Lverify_fail


    /* (p,o) = next_coordinates(p,o,move) */

    mv      a0, s0
    mv      a1, s1

    call    next_coordinates

    mv      s0, a0
    mv      s1, a1

    addi    s4, s4, 1
    j       .Lverify_loop


.Lverify_done:

    /* solved iff p == 0 && o == 0 */

    or      t0, s0, s1
    bnez    t0, .Lverify_fail

    li      a0, 1
    j       .Lverify_return


.Lverify_fail:

    li      a0, 0


.Lverify_return:

    lw      ra, 28(sp)
    lw      s4, 24(sp)
    lw      s3, 20(sp)
    lw      s2, 16(sp)
    lw      s1, 12(sp)
    lw      s0, 8(sp)

    addi    sp, sp, 32

    ret

    .size verify_solution, . - verify_solution
    .size solve_coordinates, . - solve_coordinates
    .section .bss
    .balign 4

    .globl solution_length
solution_length:
    .space 4

    .globl solution_path
solution_path:
    .space MAX_DEPTH
    .balign 4

    .globl verification_result
verification_result:
    .space 4