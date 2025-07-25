package com.terumo.camel.processor;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terumo.camel.model.Donor;
import org.apache.camel.Exchange;
import org.apache.camel.Processor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import java.util.List;

@Component
public class HtmlGenerationProcessor implements Processor {

    @Autowired
    private TemplateEngine templateEngine;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public void process(Exchange exchange) throws Exception {
        // Get the donor data from the exchange body
        String jsonBody = exchange.getIn().getBody(String.class);
        
        // Parse JSON to List of Donors
        List<Donor> allDonors = objectMapper.readValue(jsonBody, new TypeReference<List<Donor>>() {});
        
        // Filter donors to only show those with "checked-in" status
        List<Donor> checkedInDonors = allDonors.stream()
            .filter(donor -> "checked-in".equals(donor.getStatus().getValue()))
            .collect(java.util.stream.Collectors.toList());
        
        // Create Thymeleaf context and add filtered donors
        Context context = new Context();
        context.setVariable("donors", checkedInDonors);
        context.setVariable("title", "Donor Management System");
        context.setVariable("timestamp", java.time.LocalDateTime.now().toString());

        // Read operatorID cookie
        String operatorId = "unknown";
        String cookieHeader = exchange.getIn().getHeader("Cookie", String.class);
        if (cookieHeader != null) {
            String[] cookies = cookieHeader.split(";");
            for (String cookie : cookies) {
                String[] parts = cookie.trim().split("=");
                if (parts.length == 2 && "operatorID".equals(parts[0])) {
                    operatorId = parts[1];
                    break;
                }
            }
        }
        context.setVariable("operatorId", operatorId);
        
        // Process the template
        String html = templateEngine.process("donors", context);
        
        // Set the HTML as the exchange body
        exchange.getIn().setBody(html);
        exchange.getIn().setHeader("Content-Type", "text/html; charset=UTF-8");
    }
}