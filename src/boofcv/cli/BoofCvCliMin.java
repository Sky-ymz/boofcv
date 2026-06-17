/*
 * Copyright (c) 2024, BoofCV headless CLI examples.
 * Licensed under the Apache License, Version 2.0.
 */
package boofcv.cli;

import boofcv.abst.fiducial.QrCodeDetector;
import boofcv.alg.fiducial.qrcode.QrCode;
import boofcv.factory.fiducial.ConfigQrCode;
import boofcv.factory.fiducial.FactoryFiducial;
import boofcv.struct.image.GrayU8;

import java.io.IOException;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

/**
 * Minimal headless CLI: detect a single QR code in a PGM/PPM/raw-RGB image,
 * write the result as a JSON file.
 *
 * No BufferedImage. No ImageIO. No AWT. Only byte buffers and JSON strings.
 *
 * Usage:
 * <pre>
 *   java -cp boofcv_cli_min.jar boofcv.cli.BoofCvCliMin &lt;input.{pgm,ppm,rgb}&gt; &lt;output.json&gt; [width height]
 * </pre>
 * For raw RGB (no header) you must also pass width and height.
 */
public class BoofCvCliMin {

	public static void main(String[] args) {
		if (args.length < 2) {
			System.err.println("Usage: BoofCvCliMin <input.{pgm,ppm,rgb}> <output.json> [width height]");
			System.exit(2);
		}
		Path input = Paths.get(args[0]);
		Path output = Paths.get(args[1]);

		try {
			long t0 = System.nanoTime();
			PgmPpmReader.Image img = loadImage(input, args);
			byte[] gray = toGray(img);
			GrayU8 boofImage = new GrayU8(img.width, img.height);
			byte[] data = boofImage.data;
			System.arraycopy(gray, 0, data, 0, gray.length);

			var config = new ConfigQrCode();
			QrCodeDetector<GrayU8> detector = FactoryFiducial.qrcode(config, GrayU8.class);
			detector.process(boofImage);
			List<QrCode> detections = detector.getDetections();

			long durationMs = (System.nanoTime() - t0) / 1_000_000L;
			writeJson(output, input.toString(), img.width, img.height, durationMs, detections);
			System.out.println("detections=" + detections.size() + " duration_ms=" + durationMs);
		} catch (Throwable t) {
			System.err.println("ERROR: " + t.getMessage());
			t.printStackTrace(System.err);
			System.exit(1);
		}
	}

	private static PgmPpmReader.Image loadImage(Path input, String[] args) throws IOException {
		String name = input.getFileName().toString().toLowerCase();
		if (name.endsWith(".pgm") || name.endsWith(".ppm") || name.endsWith(".pnm")) {
			return PgmPpmReader.read(input);
		}
		if (name.endsWith(".rgb")) {
			if (args.length < 4) {
				throw new IOException("Raw RGB requires width and height as args[2]/args[3]");
			}
			int w = Integer.parseInt(args[2]);
			int h = Integer.parseInt(args[3]);
			return PgmPpmReader.readRawRgb(input, w, h);
		}
		throw new IOException("Unsupported file extension: " + name + " (use .pgm, .ppm, or .rgb)");
	}

	private static byte[] toGray(PgmPpmReader.Image img) {
		int n = img.width * img.height;
		byte[] gray = new byte[n];
		if (!img.color) {
			System.arraycopy(img.planes[0], 0, gray, 0, n);
			return gray;
		}
		byte[] r = img.planes[0];
		byte[] g = img.planes[1];
		byte[] b = img.planes[2];
		for (int i = 0; i < n; i++) {
			int rr = r[i] & 0xFF;
			int gg = g[i] & 0xFF;
			int bb = b[i] & 0xFF;
			// Rec. 601 luma
			int y = (rr * 299 + gg * 587 + bb * 114 + 500) / 1000;
			gray[i] = (byte) (y & 0xFF);
		}
		return gray;
	}

	private static void writeJson(Path output, String inputPath, int width, int height,
								  long durationMs, List<QrCode> detections) throws IOException {
		StringBuilder sb = new StringBuilder(256);
		sb.append("{\n");
		sb.append("  \"name\": \"BoofCvCliMin\",\n");
		sb.append("  \"input\": ").append(jsonString(inputPath)).append(",\n");
		sb.append("  \"width\": ").append(width).append(",\n");
		sb.append("  \"height\": ").append(height).append(",\n");
		sb.append("  \"duration_ms\": ").append(durationMs).append(",\n");
		sb.append("  \"detections\": [");
		for (int i = 0; i < detections.size(); i++) {
			QrCode qr = detections.get(i);
			if (i > 0) sb.append(",");
			sb.append("\n    {");
			sb.append("\"status\":\"decoded\",");
			sb.append("\"message\":").append(jsonString(qr.message == null ? "" : qr.message)).append(",");
			sb.append("\"version\":").append(qr.version).append(",");
			sb.append("\"error\":").append(qr.error == null ? "null" : jsonString(qr.error.name())).append(",");
			sb.append("\"mask\":").append(qr.mask).append(",");
			sb.append("\"corners\":[");
			for (int j = 0; j < qr.bounds.size(); j++) {
				if (j > 0) sb.append(",");
				georegression.struct.point.Point2D_F64 p = qr.bounds.get(j);
				sb.append("{\"x\":").append(p.x).append(",\"y\":").append(p.y).append("}");
			}
			sb.append("]}");
		}
		sb.append("\n  ]\n");
		sb.append("}\n");

		Files.createDirectories(output.getParent() == null ? Paths.get(".") : output.getParent());
		try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(output, StandardCharsets.UTF_8))) {
			w.print(sb);
		}
	}

	private static String jsonString(String s) {
		StringBuilder sb = new StringBuilder(s.length() + 2);
		sb.append('"');
		for (int i = 0; i < s.length(); i++) {
			char c = s.charAt(i);
			switch (c) {
				case '"':  sb.append("\\\""); break;
				case '\\': sb.append("\\\\"); break;
				case '\b': sb.append("\\b"); break;
				case '\f': sb.append("\\f"); break;
				case '\n': sb.append("\\n"); break;
				case '\r': sb.append("\\r"); break;
				case '\t': sb.append("\\t"); break;
				default:
					if (c < 0x20) sb.append(String.format("\\u%04x", (int) c));
					else sb.append(c);
			}
		}
		sb.append('"');
		return sb.toString();
	}
}
