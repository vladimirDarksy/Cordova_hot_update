/**
 * HotUpdatesHelpers.java
 * Utility methods for Hot Updates Plugin
 *
 * Contains file operations, ZIP handling, and error management utilities.
 *
 * @version 2.2.2
 * @author Mustafin Vladimir
 */
package com.getmeback.hotupdates;

import android.content.Context;
import android.util.Log;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Enumeration;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import static com.getmeback.hotupdates.HotUpdatesConstants.*;

/**
 * Helper utilities for Hot Updates plugin.
 * Provides file operations, ZIP extraction, and error handling.
 */
public class HotUpdatesHelpers {

    private HotUpdatesHelpers() {
        // Prevent instantiation
    }

    // ============================================================
    // File Operations
    // ============================================================

    /**
     * Recursively delete a file or directory.
     *
     * @param fileOrDirectory File or directory to delete
     */
    public static void deleteRecursive(File fileOrDirectory) {
        if (fileOrDirectory == null || !fileOrDirectory.exists()) return;

        if (fileOrDirectory.isDirectory()) {
            File[] children = fileOrDirectory.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursive(child);
                }
            }
        }
        fileOrDirectory.delete();
    }

    /**
     * Recursively copy directory.
     *
     * @param src Source directory
     * @param dst Destination directory
     * @throws IOException if copy fails
     */
    public static void copyDirectory(File src, File dst) throws IOException {
        if (src.isDirectory()) {
            dst.mkdirs();
            String[] children = src.list();
            if (children != null) {
                for (String child : children) {
                    copyDirectory(new File(src, child), new File(dst, child));
                }
            }
        } else {
            copyFile(src, dst);
        }
    }

    /**
     * Copy single file.
     *
     * @param src Source file
     * @param dst Destination file
     * @throws IOException if copy fails
     */
    public static void copyFile(File src, File dst) throws IOException {
        dst.getParentFile().mkdirs();

        InputStream in = new BufferedInputStream(new FileInputStream(src));
        OutputStream out = new BufferedOutputStream(new FileOutputStream(dst));

        byte[] buffer = new byte[8192];
        int bytesRead;
        while ((bytesRead = in.read(buffer)) != -1) {
            out.write(buffer, 0, bytesRead);
        }

        out.flush();
        out.close();
        in.close();
    }

    /**
     * Copy folder from assets to destination path.
     * Based on nordnetab/chcp utilities.
     *
     * @param context Android context
     * @param assetFolder Folder name in assets (e.g. "www")
     * @param destPath Destination path on filesystem
     * @throws IOException if copy fails
     */
    public static void copyAssetsFolder(Context context, String assetFolder, String destPath) throws IOException {
        String appJarPath = context.getApplicationInfo().sourceDir;
        String assetsDir = "assets/" + assetFolder;

        JarFile jarFile = new JarFile(appJarPath);
        Enumeration<JarEntry> entries = jarFile.entries();
        int prefixLength = assetsDir.length();

        while (entries.hasMoreElements()) {
            JarEntry entry = entries.nextElement();
            String name = entry.getName();

            if (!entry.isDirectory() && name.startsWith(assetsDir)) {
                String relativePath = name.substring(prefixLength);
                String destFilePath = destPath + relativePath;

                File destFile = new File(destFilePath);
                destFile.getParentFile().mkdirs();

                InputStream in = jarFile.getInputStream(entry);
                OutputStream out = new FileOutputStream(destFilePath);

                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = in.read(buffer)) != -1) {
                    out.write(buffer, 0, bytesRead);
                }

                out.close();
                in.close();
            }
        }

        jarFile.close();
    }

    // ============================================================
    // ZIP Operations
    // ============================================================

    /**
     * Validate ZIP file by checking magic bytes.
     *
     * @param zipFile ZIP file to validate
     * @return true if valid ZIP file, false otherwise
     */
    public static boolean isValidZipFile(File zipFile) {
        try {
            FileInputStream fis = new FileInputStream(zipFile);
            byte[] header = new byte[4];

            if (fis.read(header) != 4) {
                fis.close();
                return false;
            }

            fis.close();

            // Check ZIP magic bytes: 0x50 0x4B 0x03 0x04
            return header[0] == ZIP_MAGIC[0] &&
                   header[1] == ZIP_MAGIC[1] &&
                   header[2] == ZIP_MAGIC[2] &&
                   header[3] == ZIP_MAGIC[3];

        } catch (Exception e) {
            Log.e(TAG, "Failed to verify ZIP file: " + e.getMessage());
            return false;
        }
    }

    /**
     * Extract ZIP archive to destination directory.
     *
     * @param zipFile ZIP file to extract
     * @param destDir Destination directory
     * @return true if extraction successful, false otherwise
     */
    public static boolean extractZip(File zipFile, File destDir) {
        try {
            // Validate ZIP file first
            if (!isValidZipFile(zipFile)) {
                Log.e(TAG, "Invalid file format (not a ZIP archive)");
                return false;
            }

            ZipInputStream zis = new ZipInputStream(new FileInputStream(zipFile));
            ZipEntry entry;

            while ((entry = zis.getNextEntry()) != null) {
                File outFile = new File(destDir, entry.getName());

                // Security: prevent path traversal
                String canonicalDestPath = destDir.getCanonicalPath();
                String canonicalOutPath = outFile.getCanonicalPath();
                if (!canonicalOutPath.startsWith(canonicalDestPath)) {
                    Log.e(TAG, "ZIP entry outside destination directory: " + entry.getName());
                    zis.close();
                    return false;
                }

                if (entry.isDirectory()) {
                    outFile.mkdirs();
                } else {
                    outFile.getParentFile().mkdirs();

                    FileOutputStream fos = new FileOutputStream(outFile);
                    byte[] buffer = new byte[8192];
                    int bytesRead;
                    while ((bytesRead = zis.read(buffer)) != -1) {
                        fos.write(buffer, 0, bytesRead);
                    }
                    fos.close();
                }
                zis.closeEntry();
            }

            zis.close();
            return true;

        } catch (Exception e) {
            Log.e(TAG, "ZIP extraction failed: " + e.getMessage());
            return false;
        }
    }

    /**
     * Find www folder in extracted ZIP directory.
     * Checks direct path and one level of nesting.
     *
     * @param dir Directory to search in
     * @return www folder if found, null otherwise
     */
    public static File findWwwFolder(File dir) {
        // Direct www folder
        File direct = new File(dir, DIR_WWW);
        if (direct.exists() && direct.isDirectory()) {
            return direct;
        }

        // Nested www folder (one level)
        File[] children = dir.listFiles();
        if (children != null) {
            for (File child : children) {
                if (child.isDirectory()) {
                    File nested = new File(child, DIR_WWW);
                    if (nested.exists() && nested.isDirectory()) {
                        return nested;
                    }
                }
            }
        }

        return null;
    }

    // ============================================================
    // Error Handling
    // ============================================================

    /**
     * Send error to JavaScript callback.
     *
     * @param callbackContext Cordova callback context
     * @param code Error code
     * @param message Error message
     */
    public static void sendError(CallbackContext callbackContext, String code, String message) {
        try {
            JSONObject error = new JSONObject();
            error.put("code", code);
            error.put("message", message);

            JSONObject result = new JSONObject();
            result.put("error", error);

            callbackContext.error(result);
        } catch (JSONException e) {
            callbackContext.error(message);
        }
    }

    /**
     * Send error on main thread.
     *
     * @param cordova Cordova interface
     * @param callbackContext Cordova callback context
     * @param code Error code
     * @param message Error message
     */
    public static void sendErrorOnMain(CordovaInterface cordova, CallbackContext callbackContext,
                                       String code, String message) {
        cordova.getActivity().runOnUiThread(() -> sendError(callbackContext, code, message));
    }

    /**
     * Send success on main thread.
     *
     * @param cordova Cordova interface
     * @param callbackContext Cordova callback context
     */
    public static void sendSuccessOnMain(CordovaInterface cordova, CallbackContext callbackContext) {
        cordova.getActivity().runOnUiThread(callbackContext::success);
    }
}
