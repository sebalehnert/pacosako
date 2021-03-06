//! This module defines all the methods that are exposed in the C library.
//! It is the part that can be used by Julia.

use crate::{BoardPosition, DenseBoard, PacoBoard};

#[no_mangle]
pub extern "C" fn new() -> *mut DenseBoard {
    // Leaks the memory (for now) and returns a pointer.
    Box::into_raw(Box::from(DenseBoard::new()))
}

#[no_mangle]
pub extern "C" fn drop(ps: *mut DenseBoard) {
    // Looks like it does not do anything, but should actually deallocate the
    // memory of the PacoSako data structure.
    // Debug only: println!("dropping dense board.");
    let _ = unsafe { Box::from_raw(ps) };
}

#[no_mangle]
pub extern "C" fn print(ps: *mut DenseBoard) {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    println!("{:?}", ps);
}

#[no_mangle]
pub extern "C" fn clone(ps: *mut DenseBoard) -> *mut DenseBoard {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    Box::into_raw(Box::from(ps.clone()))
}

#[no_mangle]
pub extern "C" fn current_player(ps: *mut DenseBoard) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    match ps.controlling_player() {
        crate::PlayerColor::White => 1,
        crate::PlayerColor::Black => -1,
    }
}

/// Stores a 0 terminated array into the array given by the out pointer. The
/// array must have at least 128 bytes (u8) of space. If all the space is used,
/// no null termination is used.
#[no_mangle]
pub extern "C" fn legal_actions(ps: *mut DenseBoard, mut out: *mut u8) {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    if let Ok(ls) = ps.actions() {
        let mut length = 0;
        for action in ls {
            let a = match action {
                crate::PacoAction::Lift(p) => 1 + p.0,
                crate::PacoAction::Place(p) => 1 + p.0 + 64,
                crate::PacoAction::Promote(_) => 129,
            };
            unsafe {
                *out = a;
                out = out.offset(1);
                length += 1;
            }
        }
        if length < 128 {
            unsafe { *out = 0 }
        }
    } else {
        unsafe { *out = 0 }
    }
}

#[no_mangle]
pub extern "C" fn apply_action_bang(ps: *mut DenseBoard, action: u8) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    let res = if 1 <= action && action <= 64 {
        let action = crate::PacoAction::Lift(BoardPosition(action - 1));
        ps.execute(action)
    } else if action <= 128 {
        let action = crate::PacoAction::Place(BoardPosition(action - 1 - 64));
        ps.execute(action)
    } else {
        return -1;
    };
    if res.is_err() {
        -1
    } else {
        0
    }
}
