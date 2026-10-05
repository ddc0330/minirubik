    .equ RENDER, 0

    .if RENDER
    .include "ripes_led.inc"
    .endif

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

    /* Cache immutable table base addresses. */
    la      s8,  perm_next
    la      s9,  ori_next
    la      s10, perm_dist
    la      s11, ori_dist

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

.if RENDER
    /*
     * Animate only a verified solution.
     *
     * a0 = solution_path
     * a1 = solution_length
     */
    beqz    a0, .Lstart_exit

    la      a0, solution_path

    la      t0, solution_length
    lw      a1, 0(t0)

    call    render_solution
.endif

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

    add     t0, t0, s8

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

    add     t0, t0, s9

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

    add     t0, s10, a0
    lbu     t1, 0(t0)

    add     t0, s11, a1
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

    add     t5, t5, s8

    lhu     t3, 0(t5)          /* next_p */


    /* ------------------------------------------------------------
     * next_o = ori_next[o][move]
     * ------------------------------------------------------------ */

    slli    t5, t4, 4
    slli    t6, t4, 1
    add     t5, t5, t6         /* o * 18 */

    slli    t6, t1, 1
    add     t5, t5, t6

    add     t5, t5, s9

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

    add     t6, s10, t3
    lbu     a4, 0(t6)

    bltu    t5, a4, .Lida_loop


    add     t6, s11, t4
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
    .size solve_coordinates, . - solve_coordinates
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
.if RENDER

    .equ GRID_COLOR, 0x404040
    /* ============================================================
     * LED Matrix visualization
     *
     * Matrix:
     *   35 x 25
     *
     * Face order:
     *
     *   0 = U  white
     *   1 = L  orange
     *   2 = F  green
     *   3 = R  red
     *   4 = B  blue
     *   5 = D  yellow
     *
     * Each face consists of four 4 x 3 pixel facelets.
     * Therefore each complete face occupies 8 x 6 pixels.
     * ============================================================ */

    .section .rodata
    .balign 4


    /* ------------------------------------------------------------
     * RGB palette
     * ------------------------------------------------------------ */

led_palette:

    .word   0xFFFFFF           /* U: white  */
    .word   0xFF8000           /* L: orange */
    .word   0x00FF00           /* F: green  */
    .word   0xFF0000           /* R: red    */
    .word   0x0000FF           /* B: blue   */
    .word   0xFFFF00           /* D: yellow */


    /* ------------------------------------------------------------
     * Top-left pixel of each 8 x 6 face.
     *
     *             U
     *
     *       L     F     R     B
     *
     *             D
     * ------------------------------------------------------------ */

face_origin_x:
    .byte   10, 2, 10, 18, 26, 10

face_origin_y:
    .byte   1, 9, 9, 9, 9, 17


    /* ------------------------------------------------------------
     * inverse move
     *
     * solver encoding:
     *
     * 0 R    1 R2    2 R'
     * 3 B    4 B2    5 B'
     * 6 D    7 D2    8 D'
     * ------------------------------------------------------------ */

inverse_visual_move:
    .byte   2, 1, 0
    .byte   5, 4, 3
    .byte   8, 7, 6


    /* ------------------------------------------------------------
     * Quarter-turn facelet permutations
     *
     * Facelet numbering:
     *
     * U =  0..3
     * L =  4..7
     * F =  8..11
     * R = 12..15
     * B = 16..19
     * D = 20..23
     *
     * Within one face:
     *
     *       0 1
     *       2 3
     *
     * Entry i gives the old facelet copied to new facelet i.
     *
     * Three rows:
     *   row 0 = R
     *   row 1 = B
     *   row 2 = D
     * ------------------------------------------------------------ */

visual_quarter_map:

    /* R */
    .byte   0, 9, 2, 11
    .byte   4, 5, 6, 7
    .byte   8, 21, 10, 23
    .byte   14, 12, 15, 13
    .byte   3, 17, 1, 19
    .byte   20, 18, 22, 16

    /* B */
    .byte   13, 15, 2, 3
    .byte   1, 5, 0, 7
    .byte   8, 9, 10, 11
    .byte   12, 23, 14, 22
    .byte   18, 16, 19, 17
    .byte   20, 21, 4, 6

    /* D */
    .byte   0, 1, 2, 3
    .byte   4, 5, 18, 19
    .byte   8, 9, 6, 7
    .byte   12, 13, 10, 11
    .byte   16, 17, 14, 15
    .byte   22, 20, 23, 21


    /* ============================================================
     * render_solution
     *
     * a0 = solution_path
     * a1 = solution_length
     *
     * Procedure:
     *
     * 1. Start from a solved visual cube.
     * 2. Walk solution_path backwards using inverse moves.
     *    This reconstructs the input state.
     * 3. Draw the reconstructed input.
     * 4. Replay the real solver path forwards.
     * 5. Redraw after every move.
     * ============================================================ */

    .section .text
    .balign 4

    .type render_solution, @function

render_solution:

    addi    sp, sp, -16

    sw      s0, 0(sp)
    sw      s1, 4(sp)
    sw      s2, 8(sp)
    sw      ra, 12(sp)

    mv      s0, a0             /* path */
    mv      s1, a1             /* length */


    /* Begin from the solved visual cube. */

    call    init_solved_facelets


    /* ------------------------------------------------------------
     * Reconstruct the initial scrambled state.
     *
     * Start at solved and apply inverse moves in reverse order.
     * ------------------------------------------------------------ */

    mv      s2, s1


.Lrender_reconstruct:

    beqz    s2, .Lrender_initial_ready

    addi    s2, s2, -1

    add     t0, s0, s2
    lbu     t1, 0(t0)          /* solution_path[s2] */

    la      t2, inverse_visual_move
    add     t2, t2, t1
    lbu     a0, 0(t2)          /* inverse move */

    call    apply_visual_move

    j       .Lrender_reconstruct


.Lrender_initial_ready:

    /*
     * Matrix is cleared once.
     *
     * All later frames overwrite all 24 facelets, so separators
     * remain black without clearing the matrix again.
     */

    call    clear_led_matrix

    /*
     * Draw the six permanent 7 x 7 gray cube-face frames.
     * Colored 2 x 2 facelets are drawn on top.
     */
    call    draw_cube_grid

    call    draw_visual_cube
    call    render_delay


    /* ------------------------------------------------------------
     * Replay the actual solution generated by the solver.
     * ------------------------------------------------------------ */

    li      s2, 0


.Lrender_forward:

    bgeu    s2, s1, .Lrender_solution_done

    add     t0, s0, s2
    lbu     a0, 0(t0)

    call    apply_visual_move

    /*
     * Requirement:
     * redraw after every move emitted by the solver.
     */

    call    draw_visual_cube
    call    render_delay

    addi    s2, s2, 1
    j       .Lrender_forward


.Lrender_solution_done:

    lw      ra, 12(sp)
    lw      s2, 8(sp)
    lw      s1, 4(sp)
    lw      s0, 0(sp)

    addi    sp, sp, 16

    ret

    .size render_solution, . - render_solution


    /* ============================================================
     * init_solved_facelets
     *
     * visual_facelets contains one byte per facelet.
     *
     * Solved:
     *
     *   0 0 0 0       U
     *   1 1 1 1       L
     *   2 2 2 2       F
     *   3 3 3 3       R
     *   4 4 4 4       B
     *   5 5 5 5       D
     * ============================================================ */

    .type init_solved_facelets, @function

init_solved_facelets:

    la      t0, visual_facelets

    li      t1, 0              /* color / face */


.Linit_face:

    li      t2, 6
    bgeu    t1, t2, .Linit_done

    li      t2, 4


.Linit_sticker:

    beqz    t2, .Linit_next_face

    sb      t1, 0(t0)

    addi    t0, t0, 1
    addi    t2, t2, -1

    j       .Linit_sticker


.Linit_next_face:

    addi    t1, t1, 1
    j       .Linit_face


.Linit_done:

    ret

    .size init_solved_facelets, . - init_solved_facelets


    /* ============================================================
     * apply_visual_move
     *
     * a0 = move 0..8
     *
     * Move encoding:
     *
     * 0 R    1 R2    2 R'
     * 3 B    4 B2    5 B'
     * 6 D    7 D2    8 D'
     *
     * A prime move is implemented as three quarter turns.
     * ============================================================ */

    .type apply_visual_move, @function

apply_visual_move:

    addi    sp, sp, -16

    sw      s0, 4(sp)
    sw      s1, 8(sp)
    sw      ra, 12(sp)


    /* Determine face and number of quarter turns. */

    li      t0, 3
    bltu    a0, t0, .Lvisual_move_r

    li      t0, 6
    bltu    a0, t0, .Lvisual_move_b


    /* D / D2 / D' */

    li      s0, 2              /* quarter-map row D */
    addi    s1, a0, -5         /* 6->1, 7->2, 8->3 */

    j       .Lvisual_turn_loop


.Lvisual_move_r:

    li      s0, 0              /* quarter-map row R */
    addi    s1, a0, 1          /* 0->1, 1->2, 2->3 */

    j       .Lvisual_turn_loop


.Lvisual_move_b:

    li      s0, 1              /* quarter-map row B */
    addi    s1, a0, -2         /* 3->1, 4->2, 5->3 */


.Lvisual_turn_loop:

    beqz    s1, .Lvisual_move_done

    mv      a0, s0
    call    apply_visual_quarter

    addi    s1, s1, -1
    j       .Lvisual_turn_loop


.Lvisual_move_done:

    lw      ra, 12(sp)
    lw      s1, 8(sp)
    lw      s0, 4(sp)

    addi    sp, sp, 16

    ret

    .size apply_visual_move, . - apply_visual_move


    /* ============================================================
     * apply_visual_quarter
     *
     * a0 = 0 R
     *      1 B
     *      2 D
     *
     * new[i] = old[visual_quarter_map[face][i]]
     * ============================================================ */

    .type apply_visual_quarter, @function

apply_visual_quarter:

    /*
     * table row offset = face * 24
     *
     * 24 = 16 + 8
     */

    slli    t0, a0, 4
    slli    t1, a0, 3
    add     t0, t0, t1

    la      t1, visual_quarter_map
    add     t0, t0, t1        /* map row */

    la      t1, visual_facelets
    la      t2, visual_tmp

    li      t3, 0


.Lvisual_quarter_build:

    li      t4, 24
    bgeu    t3, t4, .Lvisual_quarter_copy

    /*
     * source index for new facelet t3
     */

    add     t4, t0, t3
    lbu     t4, 0(t4)

    add     t5, t1, t4
    lbu     t6, 0(t5)

    add     t5, t2, t3
    sb      t6, 0(t5)

    addi    t3, t3, 1
    j       .Lvisual_quarter_build


.Lvisual_quarter_copy:

    li      t3, 0


.Lvisual_quarter_copy_loop:

    li      t4, 24
    bgeu    t3, t4, .Lvisual_quarter_done

    add     t4, t2, t3
    lbu     t5, 0(t4)

    add     t4, t1, t3
    sb      t5, 0(t4)

    addi    t3, t3, 1
    j       .Lvisual_quarter_copy_loop


.Lvisual_quarter_done:

    ret

    .size apply_visual_quarter, . - apply_visual_quarter


    /* ============================================================
     * draw_cube_grid
     *
     * Draw six 7 x 7 dark-gray face backgrounds.
     *
     * The four 2 x 2 colored facelets are later drawn on top,
     * leaving a one-pixel gray border and central grid.
     * ============================================================ */

    .type draw_cube_grid, @function

draw_cube_grid:

    addi    sp, sp, -16

    sw      s0, 8(sp)
    sw      ra, 12(sp)

    li      s0, 0


.Lgrid_face_loop:

    li      t0, 6
    bgeu    s0, t0, .Lgrid_done

    la      t0, face_origin_x
    add     t0, t0, s0
    lbu     a0, 0(t0)

    la      t0, face_origin_y
    add     t0, t0, s0
    lbu     a1, 0(t0)

    li      a2, GRID_COLOR

    call    draw_face_background

    addi    s0, s0, 1
    j       .Lgrid_face_loop


.Lgrid_done:

    lw      ra, 12(sp)
    lw      s0, 8(sp)

    addi    sp, sp, 16

    ret

    .size draw_cube_grid, . - draw_cube_grid


    /* ============================================================
     * draw_face_background
     *
     * a0 = top-left x
     * a1 = top-left y
     * a2 = RGB color
     *
     * Draw one solid 7 x 7 square.
     * ============================================================ */

    .type draw_face_background, @function

draw_face_background:

    slli    t0, a1, 7
    slli    t1, a1, 3
    add     t0, t0, t1

    slli    t1, a1, 2
    add     t0, t0, t1

    slli    t1, a0, 2
    add     t0, t0, t1

    li      t1, LED_MATRIX_0_BASE
    add     t0, t0, t1

    li      t1, LED_MATRIX_0_WIDTH
    slli    t1, t1, 2

    li      t2, 7


.Lface_bg_row:

    beqz    t2, .Lface_bg_done

    mv      t3, t0
    li      t4, 7


.Lface_bg_column:

    beqz    t4, .Lface_bg_next_row

    sw      a2, 0(t3)

    addi    t3, t3, 4
    addi    t4, t4, -1

    j       .Lface_bg_column


.Lface_bg_next_row:

    add     t0, t0, t1

    addi    t2, t2, -1
    j       .Lface_bg_row


.Lface_bg_done:

    ret

    .size draw_face_background, . - draw_face_background


    /* ============================================================
     * draw_visual_cube
     *
     * Draw all 24 facelets.
     * ============================================================ */

    .type draw_visual_cube, @function

draw_visual_cube:

    addi    sp, sp, -32

    sw      s0, 8(sp)
    sw      s1, 12(sp)
    sw      s2, 16(sp)
    sw      s3, 20(sp)
    sw      s4, 24(sp)
    sw      ra, 28(sp)


    li      s0, 0              /* face */

    la      s2, visual_facelets


.Ldraw_cube_face:

    li      t0, 6
    bgeu    s0, t0, .Ldraw_cube_done


    /* origin x */

    la      t0, face_origin_x
    add     t0, t0, s0
    lbu     s3, 0(t0)


    /* origin y */

    la      t0, face_origin_y
    add     t0, t0, s0
    lbu     s4, 0(t0)


    li      s1, 0              /* local facelet 0..3 */


.Ldraw_cube_facelet:

    li      t0, 4
    bgeu    s1, t0, .Ldraw_cube_next_face


    /* ------------------------------------------------------------
     * Load RGB corresponding to this facelet's current color.
     * ------------------------------------------------------------ */

    lbu     t0, 0(s2)
    addi    s2, s2, 1

    la      t1, led_palette
    slli    t0, t0, 2
    add     t1, t1, t0

    lw      a2, 0(t1)


        /* ------------------------------------------------------------
     * Colored facelet positions inside a 7 x 7 face:
     *
     *   #######
     *   #00#11#
     *   #00#11#
     *   #######
     *   #22#33#
     *   #22#33#
     *   #######
     *
     * x = origin_x + 1 + column * 3
     * y = origin_y + 1 + row    * 3
     * ------------------------------------------------------------ */


    /* column = facelet & 1 */

    andi    t0, s1, 1

    /* column * 3 */

    slli    t1, t0, 1
    add     t0, t0, t1

    add     a0, s3, t0
    addi    a0, a0, 1


    /* row = facelet >> 1 */

    srli    t0, s1, 1

    /* row * 3 */

    slli    t1, t0, 1
    add     t0, t0, t1

    add     a1, s4, t0
    addi    a1, a1, 1


    call    draw_facelet


    addi    s1, s1, 1
    j       .Ldraw_cube_facelet


.Ldraw_cube_next_face:

    addi    s0, s0, 1
    j       .Ldraw_cube_face


.Ldraw_cube_done:

    lw      ra, 28(sp)
    lw      s4, 24(sp)
    lw      s3, 20(sp)
    lw      s2, 16(sp)
    lw      s1, 12(sp)
    lw      s0, 8(sp)

    addi    sp, sp, 32

    ret

    .size draw_visual_cube, . - draw_visual_cube


    /* ============================================================
     * draw_facelet
     *
     * a0 = x
     * a1 = y
     * a2 = RGB
     *
     * Draw one 4 x 3 facelet.
     *
     * LED address:
     *
     * BASE + (y * WIDTH + x) * 4
     *
     * WIDTH = 35
     * row stride = 35 * 4 = 140 bytes
     * ============================================================ */

    .type draw_facelet, @function

draw_facelet:

    /*
     * y * 140
     *
     * 140 = 128 + 8 + 4
     */

    slli    t0, a1, 7          /* y * 128 */
    slli    t1, a1, 3          /* y * 8 */

    add     t0, t0, t1

    slli    t1, a1, 2          /* y * 4 */
    add     t0, t0, t1        /* y * 140 */


    /* x * 4 */

    slli    t1, a0, 2
    add     t0, t0, t1


    /* BASE + byte offset */

    li      t1, LED_MATRIX_0_BASE
    add     t0, t0, t1


    /* row stride = WIDTH * 4 */

    li      t1, LED_MATRIX_0_WIDTH
    slli    t1, t1, 2


    /* Two pixel rows per facelet. */

    li      t2, 2

.Ldraw_facelet_row:

    beqz    t2, .Ldraw_facelet_done

    mv      t3, t0
    li      t4, 2


.Ldraw_facelet_column:

    beqz    t4, .Ldraw_facelet_next_row

    sw      a2, 0(t3)

    addi    t3, t3, 4
    addi    t4, t4, -1

    j       .Ldraw_facelet_column


.Ldraw_facelet_next_row:

    add     t0, t0, t1

    addi    t2, t2, -1
    j       .Ldraw_facelet_row


.Ldraw_facelet_done:

    ret

    .size draw_facelet, . - draw_facelet


    /* ============================================================
     * clear_led_matrix
     *
     * The entire peripheral register range is contiguous.
     * ============================================================ */

    .type clear_led_matrix, @function

clear_led_matrix:

    li      t0, LED_MATRIX_0_BASE

    li      t1, LED_MATRIX_0_SIZE
    add     t1, t1, t0


.Lclear_matrix_loop:

    bgeu    t0, t1, .Lclear_matrix_done

    sw      zero, 0(t0)

    addi    t0, t0, 4
    j       .Lclear_matrix_loop


.Lclear_matrix_done:

    ret

    .size clear_led_matrix, . - clear_led_matrix


    /* ============================================================
     * render_delay
     *
     * Delay only exists in the GUI renderer.
     *
     * Adjust this constant if the animation is too fast or slow.
     * ============================================================ */

    .type render_delay, @function

render_delay:

    li      t0, 3000000


.Lrender_delay_loop:

    addi    t0, t0, -1
    bnez    t0, .Lrender_delay_loop

    ret

    .size render_delay, . - render_delay

.endif

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
    .if RENDER

    .balign 4

visual_facelets:
    .space 24

visual_tmp:
    .space 24

.endif