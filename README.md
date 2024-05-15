# challenge-of-champions

This software was developed by Elijah Kerry for the 2024 NI Connect Challenge of the Champions.

Installation and Setup
- Install LabVIEW 2024 or later
- Run the VIPC file to install the necessary dependencies
- Ensure the hardware device is correct in Hardware Buzzer / actor core (will modify this to be automated later)

Key Features:
- Large, resizeable grid for selecting questions
- Uses NI DAQ to acquire points
- Capable of displaying text and images for the prompt
- Has a separate panel for the MC to make facilitation easy

Game Rules:
- Contestants may buzz in as soon as the question is selelected
- Once they buzz in, they ahve limited time to answer the question
- If correct, the points are added to the score
- If incorrect, points are subtracted

Implementation
This software is written using actor framework and extensively relies on subpanels for the displays and the questions.
