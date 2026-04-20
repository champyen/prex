#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    int fd = open("/usr/test_truncate.txt", O_RDWR | O_CREAT, 0644);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    
    char *large_buf = "This is a large string that will be written first to allocate some clusters. It needs to be reasonably long to test truncation properly.";
    write(fd, large_buf, 100);
    close(fd);
    
    printf("Wrote initial data.\n");
    
    fd = open("/usr/test_truncate.txt", O_RDWR | O_CREAT, 0644);
    if (fd < 0) {
        perror("open2");
        return 1;
    }
    
    char *small_buf = "Small string.";
    int len = 13;
    
    printf("Truncating to %d bytes.\n", len);
    if (ftruncate(fd, len) < 0) {
        perror("ftruncate");
        return 1;
    }
    
    printf("Writing %d bytes.\n", len);
    if (write(fd, small_buf, len) != len) {
        perror("write");
        return 1;
    }
    
    close(fd);
    printf("Success!\n");
    return 0;
}
