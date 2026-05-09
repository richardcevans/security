# Connect to the legacy Glassfish HR application

## Introduction

In this lab, we will connect to the Glassfish legacy HR application. This will involve generating an SSH key and using it to connect to the application virtual machine (VM).

### Objectives

In this lab, you will complete the following tasks:

- Setup folders and generate an SSH key-pair.
- Use the SSH to connect to the Glassfish HR application VM.
- Save the ATP TLS connection string in the Glassfish application server's properties file.

### Prerequisites

This lab assumes you have:
- Oracle Cloud Infrastructure (OCI) tenancy account
<<<<<<< HEAD
- Completion of the following previous labs: Configure the Autonomous Database instance

## Task 1: Setup folders and generate an SSH key-pair.

1. Navigate to the top right of your OCI console and select the terminal icon labelled cloud shell and wait for it to load and setup. Cloud Shell is a free-to-use browser-based terminal accessible from the Oracle Cloud Console that provides access to a Linux shell with pre-authenticated Oracle Cloud Infrastructure CLI and other useful developer tools.

    ![Open cloud shell](images/open-cloud-shell.png)
=======
- Completion of the following previous lab(s): 
    - Configure the Autonomous Database instance

## Task 1: Setup folders and generate an SSH key-pair.

1. Navigate to the top right of your OCI console and select the computer icon labelled Developer Tools, then select **Cloud Shell** and wait for it to load and setup. Cloud Shell is a free-to-use browser-based terminal accessible from the Oracle Cloud Console that provides access to a Linux shell with pre-authenticated Oracle Cloud Infrastructure CLI and other useful developer tools.

    ![Open cloud shell](images/sla-011.png "Open Cloud Shell")
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

2. Type in the following commands:

    - Create the application folder:

        ```
        <copy>mkdir myhrapp</copy> 
        ```
    - Go to the created folder:

        ```
        <copy>cd myhrapp</copy>
        ```
    
    - Generate the SSH key-pair. Press return twice to confirm and omit the passphrase option:

        ```
        <copy>ssh-keygen -b 2048 -t rsa -f myhrappkey</copy>
        ```
   
    - Set the permissions on the ssh keypair so only you, the owner, has both reading and writing capabilities.

        ```
        <copy>chmod 600 myhrappkey</copy>
        ```

<<<<<<< HEAD
    - When prompted if you want a passcode, press enter again to avoid creating one.

=======
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd
    - View the key-pair you just created:

        ```
        <copy>ls</copy>
        ```
<<<<<<< HEAD
    - Retrieve the public key and copy/paste it to a clipboard of your choosing. You will need this in future steps:
=======
    - Retrieve the public key and copy/paste it to a clipboard where it can be referred to later.
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

        ```
        <copy>cat myhrappkey.pub</copy>
        ```

<<<<<<< HEAD
    - Retrieve the private key and copy/paste it to a clipboard of your choosing. You will need this in future steps:
=======
    - Retrieve the private key and copy/paste it to a clipboard clipboard where it can be referred to later.
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

        ```
        <copy>cat myhrappkey</copy>
        ```

<<<<<<< HEAD
3. Minimize cloud shell. You will need it again for future tasks.
=======
3. Minimize cloud shell. It will be needed again for future tasks.
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

## Task 2: Create the Glassfish application instance.

1. Using the hamburger menu at the top left, navigate to **Compute** and select **Custom Images**.

<<<<<<< HEAD
    ![Navigate to custom image](images/navigate-custom-image.png)

2. Select **Import image**.

    ![Select import image](images/select-import-image.png)

3. Fill in the corresponding fields as shown in the image below (use the compartment of your choice) and select **Import image**. Use the following link for the **Object Storage URL**: https://c4u04.objectstorage.us-ashburn-1.oci.customer-oci.com/p/EcTjWk2IuZPZeNnD_fYMcgUhdNDIDA6rt9gaFj_WZMiL7VvxPBNMY60837hu5hga/n/c4u04/b/livelabsfiles/o/data-management-library-files/MyHRApp-20221201-final

    ![Create custom image](images/create-custom-image.png)

4. Once the custom image is available, use the hamburger menu at the top right to navigate to **Compute** and select **Instances**.

    ![Navigate to instances](images/navigate-instances.png)
=======
    ![Navigate to custom image](images/sla-012.png "Navigate to custom images")

2. Select **Import image**.

3. Fill in the corresponding fields as shown in the image below (use the compartment of your choice) and select **Import image**. Use the following link for the **Object Storage URL**: https://c4u04.objectstorage.us-ashburn-1.oci.customer-oci.com/p/EcTjWk2IuZPZeNnD_fYMcgUhdNDIDA6rt9gaFj_WZMiL7VvxPBNMY60837hu5hga/n/c4u04/b/livelabsfiles/o/data-management-library-files/MyHRApp-20221201-final

    ![Create custom image](images/sla-013.png "Create custom image")

4. Once the custom image is available, use the hamburger menu at the top right to navigate to **Compute** and select **Instances**.

    ![Navigate to instances](images/sla-014.png "Navigate to instances")
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

5. Select **Create instance**.

6. Fill in the corresponding fields with the following information:

    - **Name**: myhrapp
    - **Create in compartment**: Select a compartment of your choice.
    - **Placement**: Select a placement of your choice.
<<<<<<< HEAD
    - **Image**: Select **change image**. Change the image source to **Custom images**. **Make sure your compartment is the same as the one you imported the custom image to**. Select the custom Glassfish image you created in the previous steps (this can sometimes take a little bit of time to load).
    - **Shape**: Use the default shape provided.
    - **Networking**: Select **Create new virtual cloud network** and **Create a new public subnet**. Use the name `myhrapp-vcn` and a compartment of your choice. For the CIDR block, use `10.0.0.0/24`. For the public IP address, select **Assign a public IPv4 address**.
    - **Add SSH keys**: Select **Paste public keys**. copy and paste the public ssh key you created from your clipboard (make sure its the public key).
    - **Boot volume**: Make sure all options are **not** checked.

7. Select **Create**.

    ![Running instance](images/instance-running.png)
=======
    - **Image**: Select **change image**. Change the image source to **My images < Custom Images**. **Make sure your compartment is the same as the one you imported the custom image to**. Select the custom Glassfish image you created in the previous steps (this can sometimes take a little bit of time to load).
    - **Shape**: Use the default shape provided.
    - **Security**: Skip
    - **Networking**: Select **Create new virtual cloud network** and **Create a new public subnet**. Use the name `myhrapp-vcn` and a compartment of your choice. For the CIDR block, use `10.0.0.0/24`. For the public IP address, select **Assign a public IPv4 address**.
    - **Add SSH keys**: Select **Paste public key**. copy and paste the public ssh key you created from your clipboard (make sure its the public key).
    - **Storage**: Skip

7. Select **Create** and navigate to the instance page.

    ![Running instance](images/sla-015.png "Instance running") 
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

## Task 3: Save the ATP TLS connection string in the Glassfish application server's properties file.

1. Open back up your Cloud Shell terminal. Make sure you are in the `myhrapp` directory.

    ```
    <copy>cd myhrappkey</copy>
    ```

2. SSH into the Glassfish application instance using the public IP address of the instance. Whene prompted if you wish to continue the connection, type into the terminal **yes**.

    ```
    <copy>ssh -i myhrappkey opc@<PASTE INSTANCE PUBLIC IP ADDRESS HERE></copy>
    ```

<<<<<<< HEAD
    ![SSH into instance](images/ssh-into-instance.png)
=======
    ![SSH into instance](images/sla-016.png "SSH into instance")
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

    *Note:* If you are having trouble with your keys, remember that your **myhrapp** directory needs to maintain read and write privileges for the owner. If you are ever running into this issue, copy and paste the following command in your **myhrapp** directory in Cloud Shell to update read and write privileges.

    ```
    <copy>chmod 600 myhrappkey</copy>
    ```

3. Move to the `secure-legacy-app-db-vault` directory.

    ```
    <copy>cd secure-legacy-app-db-vault</copy>
    ```

4. Run the `save_connection_string.sh` script to save the TLS connection string from you ATP instance. Paste your connection string when prompted.

    ```
    <copy>./save_connection_string.sh</copy>
    ```
    
    ![Save connection string](images/connect-string.png)

5. Run the `test_connection_string.sh` script to test the application instance connection to the ATP instance. When prompted, enter your ATP ADMIN password that you created previously. Make sure you receive the correct output indicating a successful connection.

    ```
    <copy>./test_connection_string.sh</copy>
    ```

    ```
    ...
    
    SQL> SQL> Current User is...
    SQL> 
    USER
    --------------------------------------------------------------------------------
    ADMIN

    SQL> 
    SQL> Success!
    ```

    ![Test connection](images/test-connection.png)

You may now **proceed to the next lab.**

## Acknowledgements

<<<<<<< HEAD
- **Author** - Ethan Shmargad, North America Specialists Hub
- **Creator** - Richard Evans, Senior Principle Product Manager
- **Last Updated By/Date** - Ethan Shmargad, September 2022
=======
- **Author** - Ethan Shmargad, Product Manager
- **Creator** - Richard Evans, Senior Principle Product Manager
- **Last Updated By/Date** - Ethan Shmargad, April 2025
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd
