/*
 * Copyright (c) 2024, BoofCV headless CLI examples.
 * Licensed under the Apache License, Version 2.0.
 */
package boofcv.cli;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Pure-Java image reader for PGM (P5) / PPM (P6) / raw RGB formats.
 *
 * No {@link java.awt.image.BufferedImage}, no {@code javax.imageio}, no AWT.
 * Reads only what we need: a 2D array of bytes (grayscale) or 3 planes (RGB).
 *
 * Formats supported (auto-detected by magic bytes):
 * <ul>
 *   <li>P5 binary PGM: "P5\\n W H\\n MAXVAL\\n" then W*H raw grayscale bytes</li>
 *   <li>P6 binary PPM: "P6\\n W H\\n MAXVAL\\n" then W*H*3 raw RGB bytes (interleaved)</li>
 *   <li>raw RGB: no header, just W*H*3 bytes; W and H passed explicitly via
 *       filename suffix {@code .rgb_W_H} or as args</li>
 * </ul>
 *
 * The reader ignores comments (#) and any whitespace before/after numbers.
 * MAXVAL is honored up to 255 (the only one we currently scale for; values
 * above 16 are stored as-is and assumed to fit in a byte).
 */
public final class PgmPpmReader {

	public static final class Image {
		public final byte[][] planes;  // [R, G, B] for color, [Y] for gray
		public final int width;
		public final int height;
		public final boolean color;

		public Image(byte[][] planes, int width, int height, boolean color) {
			this.planes = planes;
			this.width = width;
			this.height = height;
			this.color = color;
		}

		public static Image gray(byte[] y, int width, int height) {
			return new Image(new byte[][]{y}, width, height, false);
		}

		public static Image rgb(byte[] r, byte[] g, byte[] b, int width, int height) {
			return new Image(new byte[][]{r, g, b}, width, height, true);
		}
	}

	private PgmPpmReader() {}

	private static byte[] readFully(InputStream in, int n) throws IOException {
		byte[] buf = new byte[n];
		int off = 0;
		while (off < n) {
			int r = in.read(buf, off, n - off);
			if (r < 0) {
				byte[] short_ = new byte[off];
				System.arraycopy(buf, 0, short_, 0, off);
				return short_;
			}
			off += r;
		}
		return buf;
	}

	public static Image read(Path path) throws IOException {
		try (InputStream in = Files.newInputStream(path)) {
			int m1 = in.read();
			int m2 = in.read();
			if (m1 != 'P' || (m2 != '5' && m2 != '6')) {
				throw new IOException("Not a binary PGM/PPM file: " + path
						+ " (magic=" + (char) m1 + (char) m2 + ")");
			}
			int w = readNumber(in);
			int h = readNumber(in);
			int maxval = readNumber(in);
			if (maxval <= 0 || maxval > 65535) {
				throw new IOException("Unsupported maxval=" + maxval + " (must be 1..65535)");
			}
			if (w <= 0 || h <= 0) {
				throw new IOException("Invalid image size: " + w + "x" + h);
			}
			boolean color = (m2 == '6');
			int bpp = color ? 3 : 1;
			byte[] data = readFully(in, w * h * bpp);
			System.err.println("DBG: w=" + w + " h=" + h + " bpp=" + bpp + " color=" + color
					+ " maxval=" + maxval + " want=" + (w * h * bpp) + " got=" + data.length);
			if (data.length != w * h * bpp) {
				throw new IOException("Truncated file: expected " + (w * h * bpp)
						+ " bytes, got " + data.length);
			}
			return split(data, w, h, color, maxval);
		}
	}

	/** Read raw RGB: no header. Width/height must be passed explicitly. */
	public static Image readRawRgb(Path path, int width, int height) throws IOException {
		byte[] data = Files.readAllBytes(path);
		if (data.length != width * height * 3) {
			throw new IOException("Raw RGB size mismatch: expected "
					+ (width * height * 3) + " bytes, got " + data.length);
		}
		return split(data, width, height, true, 255);
	}

	private static Image split(byte[] data, int w, int h, boolean color, int maxval) {
		int n = w * h;
		if (!color) {
			if (maxval == 255) {
				return Image.gray(data, w, h);
			}
			if (maxval < 256) {
				// rescale 1..255 into 0..255
				byte[] out = new byte[n];
				for (int i = 0; i < n; i++) {
					int v = data[i] & 0xFF;
					out[i] = (byte) ((v * 255 + maxval / 2) / maxval);
				}
				return Image.gray(out, w, h);
			}
			// 16-bit big-endian gray
			byte[] out = new byte[n];
			for (int i = 0; i < n; i++) {
				int hi = data[i * 2] & 0xFF;
				int lo = data[i * 2 + 1] & 0xFF;
				int v = (hi << 8) | lo;
				out[i] = (byte) ((v * 255 + maxval / 2) / maxval);
			}
			return Image.gray(out, w, h);
		}
		byte[] r = new byte[n];
		byte[] g = new byte[n];
		byte[] b = new byte[n];
		if (maxval < 256) {
			for (int i = 0; i < n; i++) {
				int o = i * 3;
				r[i] = data[o];
				g[i] = data[o + 1];
				b[i] = data[o + 2];
			}
		} else {
			// 16-bit big-endian RGB
			for (int i = 0; i < n; i++) {
				int o = i * 6;
				r[i] = (byte) ((((data[o] & 0xFF) << 8) | (data[o + 1] & 0xFF)) * 255 / maxval);
				g[i] = (byte) ((((data[o + 2] & 0xFF) << 8) | (data[o + 3] & 0xFF)) * 255 / maxval);
				b[i] = (byte) ((((data[o + 4] & 0xFF) << 8) | (data[o + 5] & 0xFF)) * 255 / maxval);
			}
		}
		return Image.rgb(r, g, b, w, h);
	}

	/**
	 * Reads a single non-negative integer from the stream, skipping any
	 * whitespace and comments. Always reads its own digits (caller should not
	 * pre-consume).
	 */
	private static int readNumber(InputStream in) throws IOException {
		StringBuilder sb = new StringBuilder();
		int c;
		while ((c = in.read()) != -1) {
			char ch = (char) c;
			if (ch == '#') {
				while ((c = in.read()) != -1 && c != '\n') {}
				continue;
			}
			if (Character.isWhitespace(ch)) {
				if (sb.length() == 0) continue;
				break;
			}
			if (!Character.isDigit(ch)) {
				throw new IOException("Unexpected char '" + ch + "' in PGM/PPM header");
			}
			sb.append(ch);
		}
		if (sb.length() == 0) {
			throw new IOException("Missing number in PGM/PPM header");
		}
		return Integer.parseInt(sb.toString());
	}
}
