const API_BASE_URL = "http://localhost:5000"; // Remeber to change this out

document.getElementById("uploadForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const fileInput = document.getElementById("resumeFile");
    const file = fileInput.files[0];
    
    if(!file){
        alert("please select a file.");
        return;
    }

    const allowedFile = ["application/pdf",  //Validation array type for formate & size
                         "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
    const sizeFile = 5;
    
    if (!allowedFile.includes(file.type)){
        alert("Invalid file type. Only PDF and DOCX are allowed.");
        return;
    }

    if (file.size > sizeFile * 1024 * 1024){
        alert(`File too big. Max size is ${sizeFile} MB.`);
        return;
    }

    const formData = new FormData();
    formData.append("file", file);

    //
    try {
        const res = await fetch(`${API_BASE_URL}/upload`, {
            method: "POST",
            body: formData
        });

        //Test for non-200 responses
        if (!res.ok){
            throw new Error("Server Error: " + res.status);
        }

        const data = await res.json();
        document.getElementById("response").textContent = JSON.stringify(data,null,2);
    }  catch (err){
        document.getElementById("response").textContent = "Upload failed: " + err.message;

    }
});
