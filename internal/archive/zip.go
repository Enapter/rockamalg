package archive

import (
	"archive/zip"
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

var errZipInvalidFilePath = errors.New("invalid file path in zip")

func ZipDirToBytes(path string) ([]byte, error) {
	buf := new(bytes.Buffer)
	err := zipDir(path, buf)
	return buf.Bytes(), err
}

func ZipDirToFile(path, zipFilePath string) error {
	file, err := os.Create(zipFilePath)
	if err != nil {
		return fmt.Errorf("creates archive file: %w", err)
	}
	defer file.Close()
	return zipDir(path, file)
}

func zipDir(path string, w io.Writer) error {
	zw := zip.NewWriter(w)
	defer zw.Close()

	fsys := os.DirFS(path)
	return fs.WalkDir(fsys, ".", func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}

		f, err := fsys.Open(path)
		if err != nil {
			return fmt.Errorf("open: %w", err)
		}
		defer f.Close()

		zf, err := zw.Create(path)
		if err != nil {
			return fmt.Errorf("create: %w", err)
		}

		if _, err := io.Copy(zf, f); err != nil {
			return fmt.Errorf("copy: %w", err)
		}
		return nil
	})
}

func UnzipBytesToDir(data []byte, path string) error {
	archive, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("create zip reader: %w", err)
	}
	return unzipToDir(archive, path)
}

func UnzipFileToDir(zipFile, path string) error {
	archive, err := zip.OpenReader(zipFile)
	if err != nil {
		return fmt.Errorf("create zip reader: %w", err)
	}
	defer archive.Close()
	return unzipToDir(&archive.Reader, path)
}

func UnzipFileToFilesMap(zipFile string) (map[string][]byte, error) {
	archive, err := zip.OpenReader(zipFile)
	if err != nil {
		return nil, fmt.Errorf("create zip reader: %w", err)
	}
	defer archive.Close()
	return unzipToFilesMap(&archive.Reader)
}

func unzipToFilesMap(archive *zip.Reader) (map[string][]byte, error) {
	files := make(map[string][]byte, len(archive.File))
	for _, f := range archive.File {
		if f.FileInfo().IsDir() {
			continue
		}

		fileInArchive, err := f.Open()
		if err != nil {
			return nil, fmt.Errorf("open archive file: %w", err)
		}

		file, err := io.ReadAll(fileInArchive)
		if err != nil {
			return nil, fmt.Errorf("read archive file: %w", err)
		}

		fileInArchive.Close()
		files[f.Name] = file
	}

	return files, nil
}

func unzipToDir(archive *zip.Reader, path string) error {
	for _, f := range archive.File {
		if f.FileInfo().IsDir() {
			continue
		}

		filePath, err := sanitizeArchivePath(path, f.Name)
		if err != nil {
			return err
		}

		if err := os.MkdirAll(filepath.Dir(filePath), os.ModePerm); err != nil {
			return fmt.Errorf("create dir: %w", err)
		}

		dstFile, err := os.OpenFile(filePath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return fmt.Errorf("create file: %w", err)
		}

		fileInArchive, err := f.Open()
		if err != nil {
			return fmt.Errorf("open archive file: %w", err)
		}

		//#nosec G110 -- this server for internal usage only and tests.
		if _, err := io.Copy(dstFile, fileInArchive); err != nil {
			return fmt.Errorf("copy: %w", err)
		}

		dstFile.Close()
		fileInArchive.Close()
	}

	return nil
}

// sanitizeArchivePath protects archive file pathing from "G305: Zip Slip vulnerability"
// https://snyk.io/research/zip-slip-vulnerability#go
func sanitizeArchivePath(d, t string) (string, error) {
	v := filepath.Join(d, t)
	if strings.HasPrefix(v, filepath.Clean(d)) {
		return v, nil
	}

	return "", errZipInvalidFilePath
}
