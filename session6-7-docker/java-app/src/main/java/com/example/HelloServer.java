package com.example;

import com.sun.net.httpserver.HttpServer;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

/**
 * Minimal HTTP server using the JDK's built-in com.sun.net.httpserver.
 * No framework needed: it returns a Hello World HTML page on port 8080.
 */
public class HelloServer {

    public static void main(String[] args) throws Exception {
        int port = 8080;
        // 0.0.0.0 so the server is reachable from outside the container
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", port), 0);

        server.createContext("/", exchange -> {
            String html = "<!DOCTYPE html>\n"
                    + "<html lang=\"en\">\n"
                    + "  <head><meta charset=\"utf-8\"><title>Hello World - Java</title></head>\n"
                    + "  <body>\n"
                    + "    <h1>Hello World</h1>\n"
                    + "    <p>Served by Java " + System.getProperty("java.version")
                    + " (com.sun.net.httpserver) inside a Docker container.</p>\n"
                    + "  </body>\n"
                    + "</html>\n";
            byte[] body = html.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        });

        server.start();
        System.out.println("hello-java listening on port " + port);
    }
}
