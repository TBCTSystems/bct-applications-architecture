package com.terumo.camel.processor;

import org.apache.camel.Exchange;
import org.apache.camel.Processor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

@Component
public class BarcodeScreenProcessor implements Processor {

    @Autowired
    private TemplateEngine templateEngine;

    // Base64 encoded regex patterns for each barcode type
    private static final Map<String, BarcodeConfig> BARCODE_CONFIGS = new HashMap<>();
    
    static {
        BARCODE_CONFIGS.put("collection-id", new BarcodeConfig(
            "Collection ID",
            "Xlx3ezExfSQ",
            "Scan or enter the Collection ID barcode",
            "#4CAF50"
        ));
        
        BARCODE_CONFIGS.put("plasma-container", new BarcodeConfig(
            "Plasma Container",
            "KD86MDEoPzxHVElOPlxkezh9MjEzMDBcZHsxfSl8MTAoPzxMb3ROdW1iZXI+XGR7MCwyMH0pXHUwMDFkezAsMX18MTcoPzxFeHBEYXRlWVlNTUREPlxkezZ9KXwyMSg/PFNlcmlhbE51bWJlcj5cZHswLDIwfSlcdTAwMWR7MCwxfSl7NH0k",
            "Scan or enter the Plasma Container barcode",
            "#2196F3"
        ));
        
        BARCODE_CONFIGS.put("separation-set", new BarcodeConfig(
            "Separation Set",
            "KD86MDEoPzxHVElOPlxkezh9MjEyMDBcZHsxfSl8MTAoPzxMb3ROdW1iZXI+XGR7MCwyMH0pXHUwMDFkezAsMX18MTcoPzxFeHBEYXRlWVlNTUREPlxkezZ9KXwyMSg/PFNlcmlhbE51bWJlcj5cZHswLDIwfSlcdTAwMWR7MCwxfSl7NH0k",
            "Scan or enter the Separation Set barcode",
            "#FF9800"
        ));
    }

    @Override
    public void process(Exchange exchange) throws Exception {
        String barcodeType = exchange.getIn().getBody(String.class);
        
        BarcodeConfig config = BARCODE_CONFIGS.get(barcodeType);
        if (config == null) {
            throw new IllegalArgumentException("Unknown barcode type: " + barcodeType);
        }
        
        // Create Thymeleaf context
        Context context = new Context();
        context.setVariable("barcodeType", barcodeType);
        context.setVariable("title", config.getDisplayName());
        context.setVariable("description", config.getDescription());
        context.setVariable("encodedRegex", config.getEncodedRegex());
        context.setVariable("primaryColor", config.getPrimaryColor());
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
        String html = templateEngine.process("barcode-scanner", context);
        
        // Set the HTML as the exchange body
        exchange.getIn().setBody(html);
        exchange.getIn().setHeader("Content-Type", "text/html; charset=UTF-8");
        
        // Set the regex cookie for the device
        String cookieValue = String.format("barcodeRegex_%s=%s; Path=/; HttpOnly", 
            barcodeType, config.getEncodedRegex());
        exchange.getIn().setHeader("Set-Cookie", cookieValue);
    }
    
    // Inner class to hold barcode configuration
    private static class BarcodeConfig {
        private final String displayName;
        private final String encodedRegex;
        private final String description;
        private final String primaryColor;
        
        public BarcodeConfig(String displayName, String encodedRegex, String description, String primaryColor) {
            this.displayName = displayName;
            this.encodedRegex = encodedRegex;
            this.description = description;
            this.primaryColor = primaryColor;
        }
        
        public String getDisplayName() { return displayName; }
        public String getEncodedRegex() { return encodedRegex; }
        public String getDescription() { return description; }
        public String getPrimaryColor() { return primaryColor; }
    }
}