package file

import (
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"net/url"
	"os"
	"time"

	"github.com/Azure/azure-storage-blob-go/azblob"
	"github.com/Azure/azure-storage-file-go/azfile"
)

type AzureFiles struct {
	Blob   azblob.ContainerURL
	Inbox  azfile.DirectoryURL
	Outbox azfile.DirectoryURL
}

type LocalFiles struct {
	Inbox  string
	Outbox string
}

type DwFile struct {
	Name string
	Path string
	Size int64
}

type DwFiler interface {
	ReadInbox() []DwFile
	ReadFile(file DwFile) (string, error)
	PrepareFile(file DwFile) error
	MoveFile(file DwFile) error
}

// getDirectoryUrl returns the Azure directory URL from the SAS key the Envy configuration
func getDirectoryUrl(sastoken string) azfile.DirectoryURL {
	// Anonymous credentials for SAS token access
	p := azfile.NewPipeline(azfile.NewAnonymousCredential(), azfile.PipelineOptions{})

	// Parse SAS tokens
	u, err := url.Parse(sastoken)
	if err != nil {
		log.Fatalf("Invalid SAS token [%s]: %v", sastoken, err)
	}
	return azfile.NewDirectoryURL(*u, p)
}

func getContainerUrl(sastoken string) azblob.ContainerURL {
	// Anonymous credentials for SAS token access
	p := azblob.NewPipeline(azblob.NewAnonymousCredential(), azblob.PipelineOptions{})

	// Parse SAS tokens
	u, err := url.Parse(sastoken)
	if err != nil {
		log.Fatalf("Invalid SAS token [%s]: %v", sastoken, err)
	}
	return azblob.NewContainerURL(*u, p)
}

func NewDwFiler(inbox, outbox, blob string) DwFiler {
	// Azure FILE <-> BLOB
	if blob != "" {
		return &AzureFiles{
			Blob:   getContainerUrl(blob),
			Inbox:  getDirectoryUrl(inbox),
			Outbox: getDirectoryUrl(outbox),
		}
	} else {
		return &LocalFiles{
			Inbox:  inbox,
			Outbox: outbox,
		}
	}
}

// ------------ AzureFiles -------------

func (filer *AzureFiles) ReadInbox() (files []DwFile) {
	for marker := (azfile.Marker{}); marker.NotDone(); {
		listFile, err := filer.Inbox.ListFilesAndDirectoriesSegment(context.Background(), marker, azfile.ListFilesAndDirectoriesOptions{MaxResults: 100})
		if err != nil {
			fmt.Printf("failed to list inbox - check the inbox SAS, %v\n", err)
			break
		}
		marker = listFile.NextMarker

		for _, f := range listFile.FileItems {
			files = append(files, DwFile{Name: f.Name, Path: "", Size: f.Properties.ContentLength})
		}
	}
	return files
}

func (filer *AzureFiles) ReadFile(file DwFile) (string, error) {
	fileUrl := filer.Inbox.NewFileURL(file.Name)
	props, err := fileUrl.GetProperties(context.Background())
	if err != nil {
		return "", err
	}
	// Prepare buffer large enough to hold entire file
	buffer := make([]byte, props.ContentLength())
	_, err = azfile.DownloadAzureFileToBuffer(context.Background(), fileUrl, buffer, azfile.DownloadFromAzureFileOptions{})
	if err != nil {
		return "", err
	}
	return string(buffer), nil
}

// TODO: Move file to blob storage
func (filer *AzureFiles) PrepareFile(file DwFile) (err error) {
	srcUrl := filer.Inbox.NewFileURL(file.Name)
	dstUrl := filer.Blob.NewBlobURL(file.Name)
	ctx := context.Background()

	// Move file to blob (async)
	cpId, err := dstUrl.StartCopyFromURL(ctx, srcUrl.URL(), nil, azblob.ModifiedAccessConditions{}, azblob.BlobAccessConditions{})
	if err != nil {
		log.Fatal("StartCopyFromURL failed: ", err)
	}

	st := cpId.CopyStatus()
	for st == azblob.CopyStatusPending {
		log.Println(" ¦_ Sleeping 1 sec while copying to BLOB")
		time.Sleep(time.Second * 1)
		meta, err := dstUrl.GetProperties(ctx, azblob.BlobAccessConditions{})
		if err != nil {
			log.Println(err)
			return err
		}
		st = meta.CopyStatus()
	}
	return nil
}

func (filer *AzureFiles) MoveFile(file DwFile) error {
	srcUrl := filer.Inbox.NewFileURL(file.Name)
	dstUrl := filer.Outbox.NewFileURL(file.Name)
	ctx := context.Background()

	// Move src to dst (asyc)
	cpId, err := dstUrl.StartCopy(ctx, srcUrl.URL(), azfile.Metadata{})
	if err != nil {
		return err
	}

	st := cpId.CopyStatus()
	for st == azfile.CopyStatusPending {
		log.Println(" ¦_ Sleeping 1 sec while copying to outbox (before delete)")
		time.Sleep(time.Second * 1)
		meta, err := dstUrl.GetProperties(ctx)
		if err != nil {
			log.Println(err)
			return err
		}
		st = meta.CopyStatus()
	}

	// Remove source
	_, err = srcUrl.Delete(context.Background())
	return err
}

// ------------ LocalFiles -------------

func (filer *LocalFiles) ReadInbox() (files []DwFile) {
	// Get files from container (file storage or file system?)
	dir, err := os.Open(filer.Inbox)
	if err != nil {
		log.Fatalf("Could not open inbox [%s]: %v\n", filer.Inbox, err)
	}
	localfiles, err := dir.Readdir(-1)
	dir.Close()
	if err != nil {
		log.Printf("Could not read inbox [%s]: %v\n", filer.Inbox, err)
	}

	for _, f := range localfiles {
		files = append(files, DwFile{Name: f.Name(), Path: filer.Inbox, Size: f.Size()})
	}

	return files
}

func (filer *LocalFiles) ReadFile(file DwFile) (string, error) {
	content, err := ioutil.ReadFile(file.Path + file.Name)
	if err != nil {
		log.Printf("Error reading file [%s]: %v\n", file.Name, err)
		return "", err
	}
	return string(content), nil
}

// TODO: Move file to blob storage
func (filer *LocalFiles) PrepareFile(file DwFile) (err error) {
	return nil
}

func (filer *LocalFiles) MoveFile(file DwFile) error {
	src := filer.Inbox + file.Name
	dst := filer.Outbox + file.Name
	err := os.Rename(src, dst)
	if err != nil {
		log.Fatalf("Could not rename [%s]->[%s]: %v\n", src, dst, err)
	}

	return nil
}
