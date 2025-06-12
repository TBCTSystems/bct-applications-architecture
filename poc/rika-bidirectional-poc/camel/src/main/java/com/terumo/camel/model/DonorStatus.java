package com.terumo.camel.model;

import com.fasterxml.jackson.annotation.JsonValue;

public enum DonorStatus {
    NOT_AVAILABLE("not-available"),
    CHECKED_IN("checked-in"),
    DONATING("donating"),
    DONATED("donated");
    
    private final String value;
    
    DonorStatus(String value) {
        this.value = value;
    }
    
    @JsonValue
    public String getValue() {
        return value;
    }
    
    public static DonorStatus fromValue(String value) {
        for (DonorStatus status : DonorStatus.values()) {
            if (status.value.equals(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("Unknown donor status: " + value);
    }
    
    @Override
    public String toString() {
        return value;
    }
}