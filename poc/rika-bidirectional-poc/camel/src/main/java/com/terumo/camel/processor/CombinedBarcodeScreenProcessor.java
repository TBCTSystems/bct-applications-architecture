package com.terumo.camel.processor;

import org.apache.camel.Exchange;
import org.apache.camel.Processor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

@Component
public class CombinedBarcodeScreenProcessor implements Processor {

    @Autowired
    private TemplateEngine templateEngine;

    @Override
    public void process(Exchange exchange) throws Exception {
        // Create Thymeleaf context
        Context context = new Context();
        context.setVariable("title", "Scan Barcodes");
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
        
        // Process the combined barcode template
        String html = templateEngine.process("barcode-scanner-combined", context);
        
        // Set the HTML as the exchange body
        exchange.getIn().setBody(html);
        exchange.getIn().setHeader("Content-Type", "text/html; charset=UTF-8");
    }
}