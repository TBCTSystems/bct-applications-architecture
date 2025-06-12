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
    
    public Donor() {}
    
    public Donor(Long id, Category category, String name, List<String> photoUrls, List<Tag> tags, DonorStatus status) {
        this.id = id;
        this.category = category;
        this.name = name;
        this.photoUrls = photoUrls;
        this.tags = tags;
        this.status = status;
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
    
    @Override
    public String toString() {
        return "Donor{" +
                "id=" + id +
                ", category=" + category +
                ", name='" + name + '\'' +
                ", photoUrls=" + photoUrls +
                ", tags=" + tags +
                ", status=" + status +
                '}';
    }
}