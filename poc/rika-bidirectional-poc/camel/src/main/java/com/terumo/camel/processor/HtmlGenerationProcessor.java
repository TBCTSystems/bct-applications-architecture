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
        List<Donor> donors = objectMapper.readValue(jsonBody, new TypeReference<List<Donor>>() {});
        
        // Create Thymeleaf context and add donors
        Context context = new Context();
        context.setVariable("donors", donors);
        context.setVariable("title", "Donor Management System");
        context.setVariable("timestamp", java.time.LocalDateTime.now().toString());
        
        // Process the template
        String html = templateEngine.process("donors", context);
        
        // Set the HTML as the exchange body
        exchange.getIn().setBody(html);
        exchange.getIn().setHeader("Content-Type", "text/html; charset=UTF-8");
    }
}