package file

import (
	"bytes"
	"context"
	"errors"
	"io/ioutil"
	"log"
	"net/url"
	"os"
	"time"

	"github.com/Azure/azure-storage-blob-go/azblob"
	"github.com/Azure/azure-storage-file-go/azfile"
)

var ctx = context.Background()

type AzureFiles struct {
	Blob    azblob.ContainerURL
	Inbox   azfile.DirectoryURL
	Outbox  azfile.DirectoryURL
	LogFile *DwFile
}

type LocalFiles struct {
	Inbox   string
	Outbox  string
	LogFile *DwFile
}

type DwFile struct {
	Name string
	Path string
	Size int64
	Log  bytes.Buffer
}

type DwFiler interface {
	SetLog(file DwFile)
	Write(p []byte) (int, error)
	SaveLog() error
	ReadInbox() []DwFile
	ReadFile(file DwFile) (string, error)
	ReadLog(file DwFile) (string, error)
	PreLoad(file DwFile) error
	PostLoad(file DwFile) error
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

// NewDwFiler returns either AzureFiles (if blob set) or LocalFiles
// The DwFiler interface is implemented for both types
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

// (*AzureFiles) SetLog sets the current log file
func (filer *AzureFiles) SetLog(file DwFile) {
	filer.LogFile = &file
	log.SetOutput(filer)
}
func (filer *AzureFiles) Write(p []byte) (int, error) {
	if filer.LogFile == nil {
		return 0, errors.New("FileName not set - call SetLog before writing")
	}
	return filer.LogFile.Log.Write(p)
}
func (filer *AzureFiles) SaveLog() error {
	if filer.LogFile == nil {
		return errors.New("FileName not set - call SetLog before saving")
	}
	logfile := filer.LogFile
	filer.LogFile = nil
	url := filer.Outbox.NewFileURL(logfile.Name + ".log")
	return azfile.UploadBufferToAzureFile(ctx, logfile.Log.Bytes(), url, azfile.UploadToAzureFileOptions{})
}

// (*AzureFiles) ReadInbox lists all the files located in Azure File Storage inbox and returns a []DwFile
func (filer *AzureFiles) ReadInbox() (files []DwFile) {
	log.Println("Azure: ReadInbox")
	for marker := (azfile.Marker{}); marker.NotDone(); {
		listFile, err := filer.Inbox.ListFilesAndDirectoriesSegment(ctx, marker, azfile.ListFilesAndDirectoriesOptions{MaxResults: 100})
		if err != nil {
			log.Printf("failed to list inbox - check the inbox SAS, %v\n", err)
			break
		}
		marker = listFile.NextMarker

		for _, f := range listFile.FileItems {
			files = append(files, DwFile{Name: f.Name, Path: "", Size: f.Properties.ContentLength})
		}
	}
	return files
}

// (*AzureFiles) ReadFile reads the contents of an Azure File Storage file and returns it as a string
func (filer *AzureFiles) ReadFile(file DwFile) (string, error) {
	log.Printf("Azure: ReadFile [%s]\n", file.Name)
	fileUrl := filer.Inbox.NewFileURL(file.Name)
	props, err := fileUrl.GetProperties(ctx)
	if err != nil {
		return "", err
	}
	// Prepare buffer large enough to hold entire file
	buffer := make([]byte, props.ContentLength())
	_, err = azfile.DownloadAzureFileToBuffer(ctx, fileUrl, buffer, azfile.DownloadFromAzureFileOptions{})
	if err != nil {
		return "", err
	}
	return string(buffer), nil
}

// (*AzureFiles) ReadLog reads the contents of an Azure File Storage logfile and returns it as a string
func (filer *AzureFiles) ReadLog(file DwFile) (string, error) {
	log.Printf("Azure: ReadLog [%s]\n", file.Name)
	fileUrl := filer.Outbox.NewFileURL(file.Name + ".log")
	props, err := fileUrl.GetProperties(ctx)
	if err != nil {
		return "", err
	}
	// Prepare buffer large enough to hold entire file
	buffer := make([]byte, props.ContentLength())
	_, err = azfile.DownloadAzureFileToBuffer(ctx, fileUrl, buffer, azfile.DownloadFromAzureFileOptions{})
	if err != nil {
		return "", err
	}
	return string(buffer), nil
}

// (*AzureFiles) PreLoad move file to blob storage for Sql Server to load it
// (as SQL Server currently cannot BULK insert from a Azure File Storage - only Azure Blob Storage!!)
func (filer *AzureFiles) PreLoad(file DwFile) (err error) {
	log.Printf("Azure: PreLoad [%s]\n", file.Name)
	srcUrl := filer.Inbox.NewFileURL(file.Name)
	dstUrl := filer.Blob.NewBlobURL(file.Name)

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

// (*AzureFiles) MoveBlob2Inbox is a helper for first copying Azure Blob Storage files
// generated during BULK insert (error files etc) to Azure File Storage
func (filer *AzureFiles) MoveBlob2Inbox(file DwFile) (err error) {
	log.Printf(" |_ MoveBlob2Inbox [%s]\n", file.Name)
	srcUrl := filer.Blob.NewBlobURL(file.Name)
	dstUrl := filer.Inbox.NewFileURL(file.Name)

	// Move blob to file (async)
	cpId, err := dstUrl.StartCopy(ctx, srcUrl.URL(), azfile.Metadata{})
	if err != nil {
		log.Fatal("StartCopy failed: ", err)
	}

	st := cpId.CopyStatus()
	for st == azfile.CopyStatusPending {
		log.Println(" ¦_ Sleeping 1 sec while copying BLOB to inbox (before delete)")
		time.Sleep(time.Second * 1)
		meta, err := dstUrl.GetProperties(ctx)
		if err != nil {
			log.Println(err)
			return err
		}
		st = meta.CopyStatus()
	}

	log.Printf("Azure: Delete in Blob [%s]\n", file.Name)
	_, err = srcUrl.Delete(ctx, azblob.DeleteSnapshotsOptionNone, azblob.BlobAccessConditions{})
	return err
}

// (*AzureFiles) PostLoad moves all files dumped by
func (filer *AzureFiles) PostLoad(file DwFile) (err error) {
	log.Printf("Azure: PostLoad [%s]\n", file.Name)
	for marker := (azblob.Marker{}); marker.NotDone(); {
		listBlob, err := filer.Blob.ListBlobsFlatSegment(ctx, marker, azblob.ListBlobsSegmentOptions{Prefix: file.Name + ".", MaxResults: 100})
		if err != nil {
			log.Printf("Failed to list BLOB container: %v\n", err)
			break
		}
		marker = listBlob.NextMarker

		for _, f := range listBlob.Segment.BlobItems {
			err = filer.MoveBlob2Inbox(DwFile{Name: f.Name, Size: *f.Properties.ContentLength})
			if err != nil {
				log.Printf("Failed to MoveBlob2Inbox (helper) [%s]: %v\n", f.Name, err)
			}
		}
	}

	// Delete the file itself
	log.Printf(" |_ Delete blob [%s]\n", file.Name)
	url := filer.Blob.NewBlobURL(file.Name)
	_, err = url.Delete(ctx, azblob.DeleteSnapshotsOptionNone, azblob.BlobAccessConditions{})
	if err != nil {
		log.Printf("Failed to delete Blob [%s]\n", file.Name)
	}

	return err
}

// (*AzureFiles) MoveFile moves Azure File Storage file to outbox in Azure File Storage
func (filer *AzureFiles) MoveFile(file DwFile) error {
	log.Printf("Azure: MoveFile [%s]\n", file.Name)
	srcUrl := filer.Inbox.NewFileURL(file.Name)
	dstUrl := filer.Outbox.NewFileURL(file.Name)

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
	_, err = srcUrl.Delete(ctx)
	return err
}

// ------------ LocalFiles -------------

// (*LocalFiles) SetLog sets the current log file
func (filer *LocalFiles) SetLog(file DwFile) {
	filer.LogFile = &file
	log.SetOutput(filer)
}
func (filer *LocalFiles) Write(p []byte) (int, error) {
	if filer.LogFile == nil {
		return 0, errors.New("FileName not set - call SetLog before writing")
	}
	return filer.LogFile.Log.Write(p)
}
func (filer *LocalFiles) SaveLog() error {
	if filer.LogFile == nil {
		return errors.New("FileName not set - call SetLog before saving")
	}
	logfile := filer.LogFile
	filer.LogFile = nil
	return ioutil.WriteFile(filer.Outbox+logfile.Name+".log", logfile.Log.Bytes(), 0644)
}

func (filer *LocalFiles) ReadInbox() (files []DwFile) {
	log.Println("Local: ReadInbox")
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
	log.Printf("Local: ReadFile [%s]\n", file.Name)
	content, err := ioutil.ReadFile(file.Path + file.Name)
	if err != nil {
		log.Printf("Error reading file [%s]: %v\n", file.Name, err)
		return "", err
	}
	return string(content), nil
}
func (filer *LocalFiles) ReadLog(file DwFile) (string, error) {
	log.Printf("Local: ReadLog [%s]\n", file.Name)
	content, err := ioutil.ReadFile(filer.Outbox + file.Name + ".log")
	if err != nil {
		log.Printf("Error reading file [%s]: %v\n", file.Name, err)
		return "", err
	}
	return string(content), nil
}

func (filer *LocalFiles) PreLoad(file DwFile) (err error)  { return nil }
func (filer *LocalFiles) PostLoad(file DwFile) (err error) { return nil }

func (filer *LocalFiles) MoveFile(file DwFile) error {
	log.Printf("Local: MoveFile [%s]\n", file.Name)
	src := filer.Inbox + file.Name
	dst := filer.Outbox + file.Name
	err := os.Rename(src, dst)
	if err != nil {
		log.Fatalf("Could not rename [%s]->[%s]: %v\n", src, dst, err)
	}

	return nil
}
