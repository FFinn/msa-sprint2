package com.hotelio.monolith.api;

public class BookingRejectedException extends RuntimeException {

    public BookingRejectedException(String message) {
        super(message);
    }
}
