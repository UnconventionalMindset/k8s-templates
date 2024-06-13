# Permissions

If subpath does not work, make sure
the user runnning the container is owner
or part of the group that the file is assigned at
specify the user with:
```
securityContext:
    fsGroup: 1000 # set the filesystem group
    runAsUser: 1000 # User id
    runAsGroup: 1000 # User's main group id
    runAsNonRoot: true
    supplementalGroups: [0, 999] # More group assigned to the user
    fsGroupChangePolicy: "OnRootMismatch" # Does not change file permissions unless they do not match the one of the current user
```
Make also sure the files and folders are readable by everyone otherwise you'll encounter the error:
```
failed to prepare subPath for volumeMount
```