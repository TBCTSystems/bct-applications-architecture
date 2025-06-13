package com.terumo.camel.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotNull;
import java.util.List;

public class Donor {
    
    @JsonProperty("id")
    private Long id;
    
    @JsonProperty("category")
    @NotNull
    private Category category;
    
    @JsonProperty("name")
    @NotNull
    private String name;
    
    @JsonProperty("photoUrls")
    private List<String> photoUrls;
    
    @JsonProperty("tags")
    private List<Tag> tags;
    
    @JsonProperty("status")
    @NotNull
    private DonorStatus status;

    @JsonProperty("FIRS")
    private String firs;

    @JsonProperty("LAST")
    private String last;

    @JsonProperty("DOB")
    private String dob;

    @JsonProperty("HCT")
    private String hct;

    @JsonProperty("WGHT")
    private String wght;

    @JsonProperty("HGHT")
    private String hght;

    @JsonProperty("BG")
    private String bg;
    
    public Donor() {}
    
    public Donor(Long id, Category category, String name, List<String> photoUrls, List<Tag> tags, DonorStatus status,
                 String firs, String last, String dob, String hct, String wght, String hght, String bg) {
        this.id = id;
        this.category = category;
        this.name = name;
        this.photoUrls = photoUrls;
        this.tags = tags;
        this.status = status;
        this.firs = firs;
        this.last = last;
        this.dob = dob;
        this.hct = hct;
        this.wght = wght;
        this.hght = hght;
        this.bg = bg;
    }
    
    public Long getId() {
        return id;
    }
    
    public void setId(Long id) {
        this.id = id;
    }
    
    public Category getCategory() {
        return category;
    }
    
    public void setCategory(Category category) {
        this.category = category;
    }
    
    public String getName() {
        return name;
    }
    
    public void setName(String name) {
        this.name = name;
    }
    
    public List<String> getPhotoUrls() {
        return photoUrls;
    }
    
    public void setPhotoUrls(List<String> photoUrls) {
        this.photoUrls = photoUrls;
    }
    
    public List<Tag> getTags() {
        return tags;
    }
    
    public void setTags(List<Tag> tags) {
        this.tags = tags;
    }
    
    public DonorStatus getStatus() {
        return status;
    }
    
    public void setStatus(DonorStatus status) {
        this.status = status;
    }

    public String getFirs() {
        return firs;
    }

    public void setFirs(String firs) {
        this.firs = firs;
    }

    public String getLast() {
        return last;
    }

    public void setLast(String last) {
        this.last = last;
    }

    public String getDob() {
        return dob;
    }

    public void setDob(String dob) {
        this.dob = dob;
    }

    public String getHct() {
        return hct;
    }

    public void setHct(String hct) {
        this.hct = hct;
    }

    public String getWght() {
        return wght;
    }

    public void setWght(String wght) {
        this.wght = wght;
    }

    public String getHght() {
        return hght;
    }

    public void setHght(String hght) {
        this.hght = hght;
    }

    public String getBg() {
        return bg;
    }

    public void setBg(String bg) {
        this.bg = bg;
    }
    
    @Override
    public String toString() {
        return "Donor{" +
                "id=" + id +
                ", category=" + category +
                ", name='" + name + '\'' +
                ", photoUrls=" + photoUrls +
                ", tags=" + tags +
                ", status=" + status +
                ", firs='" + firs + '\'' +
                ", last='" + last + '\'' +
                ", dob='" + dob + '\'' +
                ", hct='" + hct + '\'' +
                ", wght='" + wght + '\'' +
                ", hght='" + hght + '\'' +
                ", bg='" + bg + '\'' +
                '}';
    }
}